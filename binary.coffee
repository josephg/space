read = (buffer, offset, len) ->
  # You suck, chrome.
  if len?
    view = new DataView(buffer, offset, len)
  else if offset?
    view = new DataView(buffer, offset)
  else
    view = new DataView(buffer)
  pos = 0

  p = (size) ->
    oldPos = pos
    pos += size
    oldPos

  int32: -> view.getInt32 (p 4), true
  int16: -> view.getInt16 (p 2), true
  int8:  -> view.getInt8  (p 1)

  uint32: -> view.getUint32 (p 4), true
  uint16: -> view.getUint16 (p 2), true
  uint8:  -> view.getUint8  (p 1)

  float64: -> view.getFloat64 (p 8), true
  float32: -> view.getFloat32 (p 4), true

  skip: (x) -> pos += x

  bytestring: (len) ->
    s = new Array(len)
    for i in [0...len]
      c = @uint8()
      unless c # Skip '\0'
        @skip len - i - 1
        return s.join ''

      s[i] = String.fromCharCode c
    s.join ''

  bytesLeft: -> view.byteLength - pos


write = (buffer, offset, len) ->
  view = new DataView(buffer, offset, len)
  pos = 0

  p = (size) ->
    oldPos = pos
    pos += size
    oldPos

  int32: (value) -> view.setInt32 (p 4), value, true; @
  int16: (value) -> view.setInt16 (p 2), value, true; @
  int8: (value) -> view.setInt8 (p 1), value; @

  uint32: (value) -> view.setUint32 (p 4), value, true; @
  uint16: (value) -> view.setUint16 (p 2), value, true; @
  uint8: (value) -> view.setUint8 (p 1), value; @

  float64: (value) -> view.setFloat64 (p 8), value, true; @
  float32: (value) -> view.setFloat32 (p 4), value, true; @

  bytesLeft: -> view.byteLength - pos
  pos: -> pos

if exports?
  exports.read = read
  exports.write = write
