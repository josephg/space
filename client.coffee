canvas = document.getElementsByTagName('canvas')[0]
canvas.width = 800
canvas.height = 600

ctx = canvas.getContext '2d'

ws = new WebSocket "ws://#{window.location.host}"

space = new cp.Space

# Map from id -> body.
bodies = {}

frame = null

# MUST match the server's snapshotDelay value
snapshotDelay = 5 # Frames between subsequent snapshots.

delay = 5 # Our delay in frames behind realtime
pendingSnapshots = []

dt = 33 # dt per tick (ms). Must match server.

requestAnimationFrame = window.requestAnimationFrame or window.mozRequestAnimationFrame or
                        window.webkitRequestAnimationFrame or window.msRequestAnimationFrame

applySnapshot = (snapshot) ->
  #console.log "frame #{frame} applySnapshot #{snapshot.frame}"
  for id, s of snapshot.data
    if bodies[id]
      b = bodies[id]
    else
      throw new Error "missing data for #{id}" unless s.shapes

      b = bodies[id] = new cp.Body s.m, s.i
      b.geometry = []
      for verts in s.shapes
        b.geometry.push new cp.PolyShape b, verts, cp.v(0,0)

    b.setAngle s.a
    b.setPos cp.v(s.x, s.y)
    b.setVelocity cp.v(s.vx, s.vy)
    b.w = s.w
    b.f.x = s.fx
    b.f.y = s.fy
    b.t = s.t
    #console.log "snapshot #{b.p.x}"
  
  for id, b of bodies # Bodies that are no longer in the region sent by the server
    if snapshot.data[id]
      # Add body if it isn't in the space
      if b.space
        space.reindexShape s for s in b.shapeList
      else
        space.addBody b
        space.addShape s for s in b.geometry
    else
      if b.space
        space.removeBody b
        space.removeShape s for s in b.geometry

  console.log "time warping from #{frame} to #{snapshot.frame}" if frame isnt snapshot.frame
  frame = snapshot.frame


snapshotted = false
update = ->
  return if frame is null # No snapshots yet

  frame++

  return if frame < 0 # Delaying for extra smoothness

  snapshot = null
  skip = false

  while (pendingSnapshots.length > 0 and pendingSnapshots[0].frame <= frame) or
      pendingSnapshots.length >= 2
    skip = true
    applySnapshot pendingSnapshots.shift()

  snapshotted = skip

  space.step dt/1000 unless skip

dirty = false
draw = ->
  return unless dirty # Only draw once despite how many updates have happened
  ctx.fillStyle = 'black'
  ctx.fillRect 0, 0, 800, 600

  if frame is null or frame < 0
    ctx.font = '60px Helvetica'
    ctx.fillText 'Buffering gameplay', 0, 0, 0

  ctx.strokeStyle = 'blue'
  ctx.strokeRect 100, 100, 600, 400

  #ctx.fillStyle = 'green'
  #ctx.fillRect 100*pendingSnapshots.length, 0, 100, 100
  
  #ctx.fillStyle = 'red'
  #ctx.fillRect 25, 25, 50, 50 if snapshotted

  space.eachShape (shape) ->
    ctx.strokeStyle = 'grey'
    #ctx.fillStyle = 'rgba(0, 0, 0, 0.2)'
    #console.log "draw #{shape.body.p.x}"
    col = 255 - Math.floor shape.body.m / 100 * 255
    ctx.fillStyle = "rgb(#{col}, #{col}, #{col})"

    shape.draw()

  dirty = false

lastFrame = Date.now()

runFrame = ->
  nominalTime = lastFrame + dt
  actualTime = Date.now()
  setTimeout runFrame, Math.max(0, nominalTime - actualTime + dt)
  lastFrame = nominalTime

  update()
  dirty = true
  requestAnimationFrame draw

runFrame()

nextSnapshotFrame = 0
ws.onmessage = (msg) ->
  msg = JSON.parse msg.data
  if msg.snapshot
    snapshot =
      data: msg.snapshot
      frame: nextSnapshotFrame
    #console.log "frame #{frame} got snapshot #{snapshot.frame}"
    nextSnapshotFrame += snapshotDelay
    pendingSnapshots.push snapshot

    if frame is null
      # This is the first snapshot.
      frame = -delay


cp.PolyShape::draw = ->
  ctx.beginPath()

  verts = @tVerts
  len = verts.length

  ctx.moveTo verts[len - 2], verts[len - 1]

  for i in [0...len] by 2
    ctx.lineTo verts[i], verts[i+1]

  ctx.fill()
  ctx.stroke()


