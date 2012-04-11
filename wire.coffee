
{read, write} = require './binary'

module.exports =
  snapshot:
    id: 100
    pack: ({creates, updates, removes}) ->
      # snapshot packets have a type (1 byte) = 100,
      # then a list of object update data ({id, x, y, a, vx, vy, w})
      # then a list of object creation frames, ({id, m, i, shapes:[[verts]]})
      # then a list of objects that are being removed (ids)
      #
      # Each list starts with a short (2 bytes) with the number of elements in the list.
      # All lists are optional.

      # This is kind of inefficient -it would be better to do this in galaxy.snapshot. Eh.

      numShapes = 0
      numVerts = 0
      for c in creates
        numShapes += c.shapes.length
        for shape in c.shapes
          numVerts += shape.length

      updateBytes = if updates.length or creates.length or removes.length then 2 + updates.length * (4 + 4*6) else 0
      createBytes = if creates.length or removes.length then 2 + creates.length * (4 + 4+4 + 2) + numShapes * 2 + numVerts * 4 else 0
      removedBytes = if removes.length then 2 + removes.length * 4 else 0

      buffer = new ArrayBuffer 1 + updateBytes + createBytes + removedBytes

      writer = write buffer
      writer.uint8 @id
      
      throw new Error 'Misaligned bytes' unless writer.pos() == 1
      if updateBytes
        #console.log "Update length: #{updates.length}"
        writer.uint16 updates.length
        for s in updates
          #console.log s
          writer.uint32 s.id
          writer.float32 s[k] for k in ['x', 'y', 'a', 'vx', 'vy', 'w']

      throw new Error 'Misaligned bytes u' unless writer.pos() == 1 + updateBytes
      if createBytes
        writer.uint16 creates.length
        for s in creates
          writer.uint32 s.id
          writer.float32 s.m
          writer.float32 s.i
          writer.uint16 s.shapes.length
          for shape in s.shapes
            writer.uint16 shape.length / 2
            writer.float32 p for p in shape # The points in the polygon

      throw new Error 'Misaligned bytes c' unless writer.pos() == 1 + updateBytes + createBytes
      if removedBytes
        #removew = write buffer, 1 + updateBytes + createBytes, removedBytes
        writer.uint16 removes.length
        writer.uint32 id for id in removes

      throw new Error 'Misaligned bytes r' if writer.bytesLeft()

      buffer


