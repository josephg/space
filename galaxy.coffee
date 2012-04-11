cp = require 'chipmunk'

nextId = 0

snapshotBuffer = 1000

stats =
  skip: 0
  differ: 0

snapshotDelay = dt = null

setInterval ->
    console.log "skip: #{stats.skip} differ: #{stats.differ}"
    stats.skip = stats.differ = 0
  , 1000

cp.Body::updateSnapshot = (frame) ->
  if @snapshotFrame < frame
    s =
      id:@id
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

cp.Body::setEngine = (name, fx, fy, offsetx, offsety) ->
  unless fx or fy
    delete this.forces[name]
  else
    # The force is applied as a series of impulses, a little bit every frame.
    fx *= dt/1000
    fy *= dt/1000
    this.forces[name] = {f:cp.v(fx, fy), r:cp.v(offsetx, offsety)}

  
  #for k, {f, r} of @forces
  #    b.applyImpulse cp.v.rotate(f, b.rot), cp.v.rotate(r, b.rot)

# Used to check if we can skip a body snapshot (because its exactly where it should be
# if you just multiply out vx, vy and w)
similar = (x, y) -> Math.abs(x - y) < 1e-12

module.exports = (initialSnapshot, options) ->
  snapshotDelay = options.snapshotDelay
  dt = options.dt

  space = new cp.Space()
  bodies = {}
  
  for i in [0...100]
    mass = Math.random() * 100
    if i < 10 then mass = 50

    verts = [-25, -25, -20, 0, 0, 20, 20, 0, 25, -25]
    cp.recenterPoly verts

    body = space.addBody new cp.Body(mass, cp.momentForPoly(mass, verts, cp.v(0,0)))

    body.setPos cp.v(Math.floor(i/10) * 100, (i % 10) * 100)
    #body.w = Math.random() * 3 - 1.5
    space.addShape new cp.PolyShape(body, verts, cp.v(0,0))
    #body.vx = Math.random() * 10 - 5
    #body.vy = Math.random() * 10 - 5
    body.w_limit = 5
    body.v_limit = 200

    body.id = nextId++
    body.lastSnapshot = null
    body.snapshot = null
    body.snapshotFrame = -1
    body.forces = {}
    body.jx = body.jy = 0
    body.jw = 0

    bodies[body.id] = body


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

  getAvatar: (client) ->
    for id, body of bodies
      if !body.client?
        body.client = client
        return body

    null

  key: (client, key, down) ->
    avatar = client.avatar
    return unless avatar
    switch key
      when 'A'
        if down
          avatar.setEngine 'left', 1000, 0, 0, 20
        else
          avatar.setEngine 'left'

      when 'D'
        if down
          avatar.setEngine 'right', -1000, 0, 0, 20
        else
          avatar.setEngine 'right'

      when 'W'
        if down
          avatar.setEngine 'rear', 0, 1600, 0, -10
        else
          avatar.setEngine 'rear'

  ###
      when 'A'
        if down
          avatar.setEngine 'left', 0, 1000, 20, 0
        else
          avatar.setEngine 'left'

      when 'D'
        if down
          avatar.setEngine 'right', 0, 1000, -20, 0
        else
          avatar.setEngine 'right'
  ###

  step: (dt) ->
    for id, b of bodies
      for k, {f, r} of b.forces
        b.applyImpulse cp.v.rotate(f, b.rot), cp.v.rotate(r, b.rot)
    space.step dt / 1000

  snapshot: (frame, {seenObjects, viewport, visibleLastFrame}) ->
    visibleBodies = {}

    if viewport
      bb = cp.bb( # (l,b,r,t)
        viewport.x - snapshotBuffer,
        viewport.y - snapshotBuffer,
        viewport.x + viewport.w + snapshotBuffer,
        viewport.y + viewport.h + snapshotBuffer)

      # Gather all the bodies that the player can see
      space.bbQuery bb, cp.ALL_LAYERS, cp.NO_GROUP, (shape) ->
        visibleBodies[shape.body.id] = shape.body

    # A snapshot is made up of three lists of objects:
    # - Objects that the client hasn't seen before, that need to be created
    # - Objects with new (updated) state
    # - Objects which should be removed from the simulation for some reason.
    creates = []
    updates = []
    removes = []

    for id in visibleLastFrame when !visibleBodies[id]
      removes.push id
      seenObjects[id] = false

    visibleLastFrame.length = 0

    #console.log "Snapshot frame #{frame}"

    for id, b of visibleBodies
      visibleLastFrame.push id

      s = b.updateSnapshot frame

      # The body's snapshot is in b.snapshot and b.lastSnapshot has either the
      # previous snapshot or null.

      #console.log "seen #{id}: #{seenObjects[id]}"

      if seenObjects[id] is undefined
        # The client has never seen the object before.
        # Copy the snapshot and add extra fields for the object's geometry.

        creates.push
          id: id
          m: b.m
          i: b.i
          shapes: (shape.verts for shape in b.shapeList)

      if b.lastSnapshot and seenObjects[id] is true
        # We might be able to skip updating the object, because its just drifting.

        # Check if object fields differ
        prev = b.lastSnapshot

        mult = options.snapshotDelay * options.dt / 1000
        if s.w != prev.w or s.vx != prev.vx or s.vy != prev.vy or
            !similar(s.x, prev.x + mult * prev.vx) or
            !similar(s.y, prev.y + mult * prev.vy) or
            !similar(s.a, prev.a + mult * prev.w)
          # Nope - there's been a collision or something. Add the full object.
          updates.push s
          stats.differ++

          #console.log s.w, prev.w, '\n', s.vx, prev.vx, '\n', s.vy, prev.vy, '\n',
          #  s.x, prev.x + mult * prev.vx, '\n',
          #  s.y, prev.y + mult * prev.vy, '\n',
          #  s.a, prev.a + mult * prev.w
        else
          stats.skip++
      else
        console.log s
        updates.push s

      seenObjects[id] = true

    {creates, updates, removes}
    


