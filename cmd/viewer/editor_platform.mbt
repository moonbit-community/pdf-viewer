///|
/// Only native pixel acquisition/drawing crosses FFI. Tools, geometry,
/// wrapping, form state, edits and undo/redo live in MoonBit.
extern "js" fn native_signature_image(
  file : @js.Value,
) -> @js_async.Promise[@js.Value] =
  #| async file => {
  #|   if (!file.type.startsWith('image/')) throw new Error('Please select an image file');
  #|   const image=await createImageBitmap(file),scale=Math.min(1,1024/Math.max(image.width,image.height));
  #|   try {
  #|     const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(image.width*scale));canvas.height=Math.max(1,Math.round(image.height*scale));
  #|     canvas.getContext('2d').drawImage(image,0,0,canvas.width,canvas.height);
  #|     const bytes=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
  #|     let binary='';for(let i=0;i<bytes.length;i+=32768) binary+=String.fromCharCode(...bytes.subarray(i,i+32768));
  #|     return {width:canvas.width,height:canvas.height,rgba:btoa(binary)};
  #|   } finally {image.close();}
  #| }

///|
extern "js" fn raster_text(
  lines : FixedArray[String],
  width : Double,
  height : Double,
  size : Double,
  color : String,
) -> @js.Value =
  #| (lines,width,height,size,color) => {
  #|   const scale=Math.min(2,2048/Math.max(width,height)),canvas=document.createElement('canvas');
  #|   canvas.width=Math.max(1,Math.ceil(width*scale));canvas.height=Math.max(1,Math.ceil(height*scale));
  #|   const ctx=canvas.getContext('2d');ctx.scale(canvas.width/width,canvas.height/height);ctx.font=`${size}px sans-serif`;ctx.fillStyle=color;ctx.textBaseline='top';
  #|   for(let i=0;i<lines.length;i++) ctx.fillText(lines[i],2,2+i*size*1.2);
  #|   const bytes=ctx.getImageData(0,0,canvas.width,canvas.height).data;
  #|   let binary='';for(let i=0;i<bytes.length;i+=32768) binary+=String.fromCharCode(...bytes.subarray(i,i+32768));
  #|   return {width:canvas.width,height:canvas.height,rgba:btoa(binary)};
  #| }

///|
fn editor_text_image(
  text : String,
  rectangle : Json,
  size : Double,
  color : String,
  password : Bool,
) -> Json {
  let bounds = json_array(rectangle).map(json_number)
  let width = bounds[2] - bounds[0]
  let height = bounds[3] - bounds[1]
  let lines : Array[String] = []
  let mut line = ""
  let text = if password { [ for _ in text => "•" ].join("") } else { text }
  for char in text {
    if char == '\r' {
      continue
    }
    if char == '\n' {
      lines.push(line)
      line = ""
      continue
    }
    let next = line + char.to_string()
    if line != "" &&
      measure_width(next, "sans-serif", "400", "normal") * size > width - 4.0 {
      lines.push(line)
      line = char.to_string()
    } else {
      line = next
    }
  }
  lines.push(line)
  value_json(
    raster_text(FixedArray::from_array(lines), width, height, size, color),
  )
}

///|
extern "js" fn native_field_values(
  control : @dom.Element,
) -> FixedArray[String] =
  #| control => control.tagName==='SELECT'?[...control.selectedOptions].map(option=>option.value):[control.value]

///|
extern "js" fn native_field_indices(control : @dom.Element) -> FixedArray[Int] =
  #| control => [...control.selectedOptions].map(option=>option.index)

///|
extern "js" fn native_field_checked(control : @dom.Element) -> Bool =
  #| control => control.checked

///|
extern "js" fn native_edit_target(
  event : @dom.PointerEvent,
) -> @js.Nullable[@dom.Element] =
  #| event => event.target instanceof Element?event.target:null

///|
extern "js" fn native_preview(
  canvas : @dom.Element,
  points : FixedArray[Double],
  matrix : FixedArray[Double],
  color : String,
  width : Double,
  rectangle : Bool,
) -> Unit =
  #| (canvas,points,matrix,color,width,rectangle) => {
  #|   const ctx=canvas.getContext('2d');ctx.resetTransform();ctx.clearRect(0,0,canvas.width,canvas.height);ctx.setTransform(...matrix);ctx.strokeStyle=color;ctx.fillStyle=color;ctx.lineWidth=width;ctx.lineCap='round';ctx.lineJoin='round';
  #|   if(rectangle) {ctx.globalAlpha=.2;ctx.fillRect(points[0],points[1],points[2]-points[0],points[3]-points[1]);ctx.globalAlpha=1;ctx.strokeRect(points[0],points[1],points[2]-points[0],points[3]-points[1]);}
  #|   else {ctx.beginPath();for(let i=0;i<points.length;i+=2) i?ctx.lineTo(points[i],points[i+1]):ctx.moveTo(points[i],points[i+1]);ctx.stroke();}
  #| }
