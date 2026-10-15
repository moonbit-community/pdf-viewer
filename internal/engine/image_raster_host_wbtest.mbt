///|
#cfg(target="js")
extern "js" fn raster_test_install() -> Unit =
  #| () => {
  #|   const entries=new WeakMap(),uris=new Map();let next=0;
  #|   globalThis.__moonbit_pdf_rasters={enabled:true,
  #|     capture(w,h,c,rows,encode){if(c!==2&&c!==6)return null;const marker=new Uint8Array(1),uri='pdf-raster:test:'+ ++next;entries.set(marker,uri);uris.set(uri,encode);return marker;},
  #|     uri(marker){return entries.get(marker)||'';},
  #|     embed(uri){const encode=uris.get(uri);if(!encode)return uri;let s='';for(const b of encode())s+=String.fromCharCode(b);return 'data:image/png;base64,'+btoa(s);}
  #|   };
  #| }

///|
#cfg(target="js")
extern "js" fn raster_test_disable() -> Unit =
  #| () => {globalThis.__moonbit_pdf_rasters.enabled=false;}

///|
#cfg(target="js")
extern "js" fn raster_test_reset() -> Unit =
  #| () => {delete globalThis.__moonbit_pdf_rasters;}

///|
#cfg(target="js")
test "browser raster hooks preserve lazy PNG bytes and self-contained SVG" {
  raster_test_install()
  defer raster_test_reset()
  let rows = b"\x00\xFF\x00\x40\x20\x80\xFF"
  let marker = pdf_png_of_scanline_bytes(2, 1, 2, rows)
  let uri = pdf_image_data_uri("image/png", marker)
  assert_true(uri.has_prefix("pdf-raster:test:"))
  raster_test_disable()
  let png = pdf_png_of_scanline_bytes(2, 1, 2, rows)
  assert_eq(pdf_image_embedded_uri(uri), pdf_image_data_uri("image/png", png))
  let resource = colour_image_fixture("/DeviceRGB", 8, "FF0040", width=1)
  let page = annotation_test_page(
    [],
    resources="<< /XObject << /Im1 5 0 R >> >>",
    contents="/Im1 Do",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /ASCIIHexDecode",
        "FF0040>",
      ),
    ],
  )
  guard page.items is [Image(image)] else { fail("missing image") }
  let image = { ..image, resource: Some({ ..resource, data_uri: Some(uri), }), }
  let exported = { ..page, items: [Image(image)], }.render_svg()
  assert_true(!exported.contains("pdf-raster:"))
  assert_true(exported.contains(pdf_image_data_uri("image/png", png)))
  let masked = pdf_svg_alpha_mask_data_uri(image, uri, uri)
  let masked_svg = @utf8.decode(@base64.decode(masked[26:]))
  assert_true(!masked_svg.contains("pdf-raster:"))
  assert_true(masked_svg.contains(pdf_image_data_uri("image/png", png)))
}
