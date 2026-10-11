///|
fn editor_security_fixture() -> PdfViewerDocument raise {
  annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [4 0 R] /DA (/Helv 12 Tf 0 g) >> >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Annots [4 0 R 5 0 R] >>",
    "<< /Subtype /Widget /Rect [10 20 160 50] /FT /Tx /T (person) /V (Before) >>",
    "<< /Subtype /FreeText /Rect [10 70 160 100] /Contents (Before) /DA (/Helv 12 Tf 0 g) >>",
  ])
}

///|
fn editor_security_encrypt(
  source : PdfViewerDocument,
  method : Int,
  denied : Array[@crypt_core.PdfPermission],
  user? : Bytes = b"reader",
) -> Bytes raise @core.PdfError {
  let iv = @pdflite.pdf_deterministic_aes_iv_provider_from_seed(
    b"editor-test-iv",
  )
  let random = @pdflite.pdf_deterministic_aesv3_random_provider_from_seed(
    b"editor-test-random",
  )
  match method {
    0 =>
      @pdflite.pdf_write_encrypted_40bit_document(
        source.document,
        user,
        b"owner",
        denied,
        file_id=b"editor-file-id",
      )
    1 =>
      @pdflite.pdf_write_encrypted_128bit_document(
        source.document,
        user,
        b"owner",
        denied,
        file_id=b"editor-file-id",
      )
    2 =>
      @pdflite.pdf_write_encrypted_128bit_r4_document(
        source.document,
        user,
        b"owner",
        denied,
        encrypt_metadata=false,
        file_id=b"editor-file-id",
      )
    3 =>
      @pdflite.pdf_write_encrypted_aesv2_document_with_iv_provider(
        source.document,
        user,
        b"owner",
        denied,
        iv,
        encrypt_metadata=false,
        file_id=b"editor-file-id",
      )
    _ =>
      @pdflite.pdf_write_encrypted_aesv3_document_with_providers(
        source.document,
        user,
        b"owner",
        denied,
        random,
        iv,
        iso=method == 5,
        encrypt_metadata=false,
        file_id=b"editor-file-id",
      )
  }
}

///|
test "editor reencrypts RC4 and AES snapshots retaining both passwords and original encryption settings" {
  let source = editor_security_fixture()
  for method in 0..<6 {
    let bytes = editor_security_encrypt(source, method, [@crypt_core.PdfNoCopy])
    let original = open_document_with_passwords(
      bytes,
      user_password=Some(b"reader"),
    )
    let before = original.document.saved_encryption.unwrap().values
    let edited = original.with_editor_changes([
      {
        "kind": "field",
        "id": "object:4",
        "page": 1,
        "values": ["MoonBit secret value"],
      },
      {
        "kind": "update",
        "id": "object:5",
        "page": 1,
        "contents": "Secret annotation",
      },
    ])
    let saved = edited.save_bytes(
      aes_iv_provider=@pdflite.pdf_deterministic_aes_iv_provider_from_seed(
        b"save-test-only",
      ),
    )
    assert_true((try? open_document(saved)) is Err(_))
    assert_true(
      (try? open_document_with_passwords(saved, user_password=Some(b"wrong")))
      is Err(_),
    )
    assert_true(!@utf8.decode_lossy(saved).contains("MoonBit secret value"))
    for owner in [false, true] {
      let reopened = if owner {
        open_document_with_passwords(saved, owner_password=Some(b"owner"))
      } else {
        open_document_with_passwords(saved, user_password=Some(b"reader"))
      }
      assert_eq(reopened.document.saved_encryption.unwrap().values, before)
      let annotations = reopened.page(1).unwrap().annotations
      assert_eq(annotations[0].field_value, Some("MoonBit secret value"))
      assert_eq(annotations[1].contents, Some("Secret annotation"))
      assert_true(
        annotations.all(annotation => annotation.appearance is Some(_)),
      )
    }
    assert_eq(
      original.page(1).unwrap().annotations[0].field_value,
      Some("Before"),
    )
    assert_eq(original.document.saved_encryption.unwrap().values, before)
    assert_eq(
      original.with_editor_changes([]).editor_permissions(),
      original.editor_permissions(),
    )
  }
}

///|
test "editor enforces encrypted user permissions without trusting an incorrect owner password" {
  let bytes = editor_security_encrypt(editor_security_fixture(), 3, [
    @crypt_core.PdfNoAnnot,
  ])
  let user = open_document_with_passwords(
    bytes,
    user_password=Some(b"reader"),
    owner_password=Some(b"wrong"),
  )
  assert_eq(user.editor_permissions(), {
    encrypted: true,
    annotations: false,
    forms: true,
  })
  guard user.editor_page_json(1) is Some(Array([field, note])) else {
    fail("missing editor entries")
  }
  assert_eq(pdf_edit_entry(field, "editable"), Json::boolean(true))
  assert_eq(pdf_edit_entry(note, "editable"), Json::boolean(false))
  assert_true(
    (try? user.with_editor_changes([
      {
        "kind": "field",
        "id": "object:4",
        "page": 1,
        "values": ["Should be atomic"],
      },
      { "kind": "delete", "id": "object:5", "page": 1 },
    ]))
    is Err(_),
  )
  assert_eq(user.page(1).unwrap().annotations[0].field_value, Some("Before"))
  let filled = user.with_editor_changes([
    { "kind": "field", "id": "object:4", "page": 1, "values": ["Allowed"] },
  ])
  assert_eq(filled.page(1).unwrap().annotations[0].field_value, Some("Allowed"))
  let denied = editor_security_encrypt(editor_security_fixture(), 4, [
    @crypt_core.PdfNoAnnot,
    @crypt_core.PdfNoForms,
  ])
  let reader = open_document_with_passwords(
    denied,
    user_password=Some(b"reader"),
  )
  assert_eq(reader.editor_permissions(), {
    encrypted: true,
    annotations: false,
    forms: false,
  })
  assert_true(
    (try? reader.with_editor_changes([
      { "kind": "field", "id": "object:4", "page": 1, "values": ["Forbidden"] },
    ]))
    is Err(_),
  )
  let owner = open_document_with_passwords(
    denied,
    user_password=Some(b"reader"),
    owner_password=Some(b"owner"),
  )
  assert_eq(owner.editor_permissions(), {
    encrypted: true,
    annotations: true,
    forms: true,
  })
  assert_eq(
    owner
    .with_editor_changes([
      { "kind": "field", "id": "object:4", "page": 1, "values": ["Owner"] },
    ])
    .page(1)
    .unwrap().annotations[0].field_value,
    Some("Owner"),
  )
  // Annotation permission also permits filling fields when bit 9 is denied.
  let annot = open_document_with_passwords(
    editor_security_encrypt(editor_security_fixture(), 1, [
      @crypt_core.PdfNoForms,
    ]),
    user_password=Some(b"reader"),
  )
  assert_true(annot.editor_permissions().forms)
}

///|
test "editor AES saves require fresh IV providers and never corrupt the editable snapshot on failure" {
  let original = open_document_with_passwords(
    editor_security_encrypt(editor_security_fixture(), 3, []),
    user_password=Some(b"reader"),
  )
  let edited = original.with_editor_changes([
    { "kind": "field", "id": "object:4", "page": 1, "values": ["After"] },
  ])
  assert_true((try? edited.save_bytes()) is Err(_))
  assert_true(
    (try? edited.save_bytes(aes_iv_provider=(_, _, _) => b"too short"))
    is Err(_),
  )
  let counter = Ref(0)
  let provider : (Int, Int, Int) -> Bytes raise @core.PdfError = fn(_, _, _) {
    counter.val += 1
    Bytes::make(16, counter.val.to_byte())
  }
  let first = edited.save_bytes(aes_iv_provider=provider)
  let second = edited.save_bytes(aes_iv_provider=provider)
  assert_true(first != second)
  assert_eq(
    open_document_with_passwords(second, user_password=Some(b"reader"))
    .page(1)
    .unwrap().annotations[0].field_value,
    Some("After"),
  )
  assert_eq(edited.page(1).unwrap().annotations[0].field_value, Some("After"))
  assert_true(!edited.document.is_encrypted())
}

///|
test "editor opens owner-protected PDFs with an empty user password and preserves restrictions when saving" {
  for method in [1, 3, 5] {
    let bytes = editor_security_encrypt(
      editor_security_fixture(),
      method,
      [@crypt_core.PdfNoAnnot],
      user=b"",
    )
    let original = open_document(bytes)
    assert_eq(original.editor_permissions(), {
      encrypted: true,
      annotations: false,
      forms: true,
    })
    let edited = original.with_editor_changes([
      { "kind": "field", "id": "object:4", "page": 1, "values": ["No prompt"] },
    ])
    let saved = edited.save_bytes(
      aes_iv_provider=@pdflite.pdf_deterministic_aes_iv_provider_from_seed(
        b"blank-user-test",
      ),
    )
    assert_eq(
      open_document(saved).page(1).unwrap().annotations[0].field_value,
      Some("No prompt"),
    )
    assert_eq(
      open_document(saved).editor_permissions(),
      original.editor_permissions(),
    )
    assert_true(
      open_document_with_passwords(saved, owner_password=Some(b"owner")).editor_permissions().annotations,
    )
  }
}
