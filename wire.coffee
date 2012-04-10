
{read, write} = require './binary'

module.exports =
  snapshot:
    id: 100
    pack: (data) ->
      # snapshot packets have a type (1 byte) = 100,
      # then a list of object update data.
      # then a list of object creation frames,
      # then a list of objects that are being removed
      #
      # Each list starts with a short (2 bytes) with the number of elements in the list.
      # All lists are optional.

      # This is kind of inefficient -it would be better to do this in galaxy.snapshot. Eh.

      numUpdates = 0 # list of {id, x, y, a, vx, vy, w}
      numCreates = 0 # list of {id, m, i, shapes:[[verts]]}. Each shape is
      numRemoved = 0 # ids

      numShapes = 0
      numVerts = 0

      for id, s of data
        if s == null
          numRemoved++
        else
          if s.shapes
            numCreates++
            for shape in s.shapes
              numShapes++
              numVerts += shape.length
          numUpdates++

      buffer = new ArrayBuffer 1 + # Packet type (100)
        # Way nicer if I could just use a resizable array or something. Eh.
        (updateBytes = if numUpdates or numCreates or numRemoved then 2 + numUpdates * (4 + 4*6) else 0) +
        (createBytes = if numCreates or numRemoved then 2 + numCreates * (4 + 4+4 + 2) + numShapes * 2 + numVerts * 4 else 0) +
        (removedBytes = if numRemoved then 2 + numRemoved * 4 else 0)

      header = write buffer, 0, 1
      header.uint8 @id
      
      if updateBytes
        updates = write buffer, 1, updateBytes
        updates.uint16 numUpdates

      if createBytes
        creates = write buffer, 1 + updateBytes, createBytes
        creates.uint16 numCreates

      if removedBytes
        removed = write buffer, 1 + updateBytes + createBytes, removedBytes
        removed.uint16 numRemoved

      for id, s of data
        if s == null
          removed.uint32 id
        else
          if s.shapes
            creates.uint32 id
            creates.float32 s.m
            creates.float32 s.i
            creates.uint16 s.shapes.length
            for shape in s.shapes
              creates.uint16 shape.length / 2
              creates.float32 p for p in shape # The points in the polygon

          updates.uint32 id
          updates.float32 s[k] for k in ['x', 'y', 'a', 'vx', 'vy', 'w']
      
      throw new Error 'Misaligned bytes' if updates?.bytesLeft() or creates?.bytesLeft() or removed?.bytesLeft()

      buffer


