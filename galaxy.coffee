cp = require 'chipmunk'

nextId = 0

snapshotBuffer = 1000

stats =
  skip: 0
  differ: 0

setInterval ->
    console.log "skip: #{stats.skip} differ: #{stats.differ}"
    stats.skip = stats.differ = 0
  , 1000

cp.Body::updateSnapshot = (frame, snapshotDelay) ->
  if @snapshotFrame < frame
    s =
      a:@a # angle
      x:@p.x # Position
      y:@p.y
      vx:@vx # Velocity
      vy:@vy
      w:@w # angular momentum
      #fx:@f.x # Force
      #fy:@f.y
      #t:@t # torque

    @lastSnapshot = if @snapshotFrame is frame - snapshotDelay
      @snapshot
    else
      null

    @snapshotFrame = frame
    @snapshot = s
  else
    @snapshot

# Used to check if we can skip a body snapshot (because its exactly where it should be
# if you just multiply out vx, vy and w)
similar = (x, y) -> Math.abs(x - y) < 1e-12

module.exports = (initialSnapshot, options) ->
  space = new cp.Space()
  
  for i in [0...100]
    width = 50
    height = 50
    mass = Math.random() * 100

    body = space.addBody new cp.Body(mass, cp.momentForBox(mass, width, height))
    body.setPos cp.v(Math.floor(i/10) * 100, (i % 10) * 100)
    body.w = Math.random() * 3 - 1.5
    space.addShape new cp.BoxShape(body, width, height)
    body.vx = Math.random() * 10 - 5
    body.vy = Math.random() * 10 - 5

    body.id = nextId++
    body.lastSnapshot = null
    body.snapshot = null
    body.snapshotFrame = -1


  ###
  width = 10
  height = 400
  mass = 1
  body = space.addBody new cp.Body(mass, cp.momentForBox(mass, width, height))
  body.setPos cp.v(100, 100)
  body.id = nextId++
  space.addShape new cp.BoxShape(body, width, height)
  body.vx = 60
  body.vy = 0
  ###


  step: (dt) ->
    space.step dt / 1000

  snapshot: (frame, {seenObjects, viewport, visibleLastFrame}) ->
    bodies = {}

    if viewport
      bb = cp.bb( # (l,b,r,t)
        viewport.x - snapshotBuffer,
        viewport.y - snapshotBuffer,
        viewport.x + viewport.w + snapshotBuffer,
        viewport.y + viewport.h + snapshotBuffer)

      # Gather all the bodies that the player can see
      space.bbQuery bb, cp.ALL_LAYERS, cp.NO_GROUP, (shape) ->
        bodies[shape.body.id] = shape.body

    snapshot = {}

    for id in visibleLastFrame when !bodies[id]
      snapshot[id] = null
      seenObjects[id] = false

    visibleLastFrame.length = 0

    #console.log "Snapshot frame #{frame}"

    for id, b of bodies
      visibleLastFrame.push id

      s = b.updateSnapshot frame, options.snapshotDelay

      # The body's snapshot is in b.snapshot and b.lastSnapshot has either the
      # previous snapshot or null.

      #console.log "seen #{id}: #{seenObjects[id]}"

      if seenObjects[id] is undefined
        # The client has never seen the object before.
        # Copy the snapshot and add extra fields for the object's geometry.
        snapshot[id] =
          a:s.a
          x:s.x
          y:s.y
          vx:s.vx
          vy:s.vy
          w:s.w

        snapshot[id].m = b.m # Mass
        snapshot[id].i = b.i # Moment
        snapshot[id].shapes = (s.verts for s in b.shapeList)

      else if b.lastSnapshot and seenObjects[id] is true
        # Check if object fields differ
        prev = b.lastSnapshot

        mult = options.snapshotDelay * options.dt / 1000
        if s.w != prev.w or s.vx != prev.vx or s.vy != prev.vy or
            !similar(s.x, prev.x + mult * prev.vx) or
            !similar(s.y, prev.y + mult * prev.vy) or
            !similar(s.a, prev.a + mult * prev.w)
          # There's been a collision or something. Add the full object.
          snapshot[id] = s
          stats.differ++

          #console.log s.w, prev.w, '\n', s.vx, prev.vx, '\n', s.vy, prev.vy, '\n',
          #  s.x, prev.x + mult * prev.vx, '\n',
          #  s.y, prev.y + mult * prev.vy, '\n',
          #  s.a, prev.a + mult * prev.w
        else
          # The object's state can be inferred from the previous frame.
          stats.skip++
      else
        snapshot[id] = s

      seenObjects[id] = true

    snapshot
    


