///|
// Credentials remain private and are never included in diagnostics or JSON.
struct PdfEditorSecurity {
  password : Bytes
  owner_authenticated : Bool
}

///|
/// Editing permissions after password authentication. Owners can edit all
/// supported annotations and fields; user permissions retain the original /P.
pub struct PdfEditorPermissions {
  encrypted : Bool
  annotations : Bool
  forms : Bool
} derive(Eq, Debug, ToJson)

///|
pub fn PdfViewerDocument::editor_permissions(
  self : PdfViewerDocument,
) -> PdfEditorPermissions {
  let encrypted = self.document.saved_encryption is Some(_) ||
    self.document.is_encrypted()
  if self.document.is_encrypted() || (encrypted && self.editor_security is None) {
    return { encrypted, annotations: false, forms: false, }
  }
  match (self.document.saved_encryption, self.editor_security) {
    (Some(saved), Some(security)) if !security.owner_authenticated => {
      let denied = @crypt_core.pdf_permissions_of_p(saved.values.permissions)
      let annotations = !denied.contains(@crypt_core.PdfNoAnnot)
      {
        encrypted,
        annotations,
        forms: annotations || !denied.contains(@crypt_core.PdfNoForms),
      }
    }
    _ => { encrypted, annotations: true, forms: true, }
  }
}

///|
fn PdfViewerDocument::pdf_edit_require_unlocked(
  self : PdfViewerDocument,
) -> Unit raise @core.PdfError {
  if self.document.is_encrypted() ||
    (self.document.saved_encryption is Some(_) && self.editor_security is None) {
    raise @core.SoftError("Editing requires an authenticated PDF password")
  }
}

///|
fn pdf_edit_require_iv_provider(
  provider : ((Int, Int, Int) -> Bytes raise @core.PdfError)?,
) -> ((Int, Int, Int) -> Bytes raise @core.PdfError) raise @core.PdfError {
  guard provider is Some(provider) else {
    raise @core.SoftError(
      "AES saving requires a cryptographically secure IV provider",
    )
  }
  provider
}
