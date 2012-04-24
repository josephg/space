canvas = document.getElementsByTagName('canvas')[0]
canvas.width = 1024
canvas.height = 768

ctx = canvas.getContext '2d'

ws = new WebSocket "ws://#{window.location.host}"
ws.binaryType = 'arraybuffer'

ws.onerror = (e) -> console.log e

# Map from id -> body.
bodies = {}

frame = 0
prevSnapshot = {frame:-5, data:{}}

# MUST match the server's snapshotDelay value
snapshotDelay = 5 # Frames between subsequent snapshots.

delay = 5 # Our delay in frames behind realtime
pendingSnapshots = []

dt = 33 # dt per tick (ms). Must match server.
fmult = dt / 1000

viewportX = viewportY = 0

requestAnimationFrame = window.requestAnimationFrame or window.mozRequestAnimationFrame or
                        window.webkitRequestAnimationFrame or window.msRequestAnimationFrame

shipTypes = "ship bullet".split(' ')

lastFrameTime = 0

radar = []

models = [
  {verts:[-25, -25, -20, 0, 0, 20, 20, 0, 25, -25]}, # Ship
  {verts:[-3, -5, 0, 5, 3, -5]}, # bullet
]
m.offset = cp.v.neg cp.centroidForPoly m.verts for m in models

dirty = false

packetHeaders =
  100:
    name: 'snapshot'
    read: (r) ->
      data = {}

      flags = r.uint8()

      if flags & 0x1 # Update frames
        for [0...r.uint16()]
          # Read an update packet.
          id = r.uint32()
          data[id] = s = {u:[]}
          bits = r.uint8() # Contains 1 bit set for each frame's data
          for f in [0...snapshotDelay]
            x = 1<<f
            if bits & x
              s.u[f] = {x:r.float32(), y:r.float32(), a:r.float32()}
              unless bits & (x<<1)
                s.u[f][k] = r.float32() for k in ['dx', 'dy', 'da', 'ddx', 'ddy', 'dda']
 
      if flags & 0x2 # Create frames
        for [0...r.uint16()]
          # Create packets
          id = r.uint32()
          throw new Error "Got a create and an update for #{id}" if data[id]
          data[id] = s = {} # We should never get a create and an 
          s.type = shipTypes[r.uint8()]
          s.model = models[r.uint8()]
          #s.m = r.float32()
          #s.i = r.float32()
          s.v_limit = r.float32()
          s.w_limit = r.float32()
          s[k] = r.float32() for k in ['x', 'y', 'a', 'dx', 'dy', 'da', 'ddx', 'ddy', 'dda']

      if flags & 0x4 # Remove frames
        for [0...r.uint16()]
          # Remove objects.
          id = r.uint32()
          data[id] = null

      if flags & 0x8 # Ship data
        for [0...r.uint16()]
          id = r.uint32()
          s = (data[id] or= {id})
          s.loadout = r.bytestring 5*6
          s.label = r.bytestring 8
          s.color = "rgb(#{r.uint8()}, #{r.uint8()}, #{r.uint8()})"
          #console.log "ship data for #{id} #{s.label}"

      if flags & 0x10 # Radar
        rad = []
        for [0...r.uint16()]
          h =
            x: r.float32()
            y: r.float32()
            heat: r.float32()
          rad.push h

      throw new Error 'Misaligned bytes' unless r.bytesLeft() is 0
      {data, radar:rad}

  101: # lua messages.
    name: 'lua message'
    read: (r) ->
      # bleh ignore for now.
  
  102:
    name: 'set avatar'
    read: (r) -> r.uint32()


readPacket = (data) ->
  r = read data
  type = r.uint8()
  unless packetHeaders[type]
    console.error 'Not a valid message type!'
    return

  type: packetHeaders[type].name
  data: packetHeaders[type].read r

applySnapshot = (snapshot) ->
  throw new Error "Snapshot #{snapshot.frame} preloaded at the wrong frame (#{frame})" unless frame is snapshot.frame

  if prevSnapshot
    if snapshot.frame isnt prevSnapshot.frame + snapshotDelay
      throw new Error "Snapshots not applied in order: #{prevSnapshot.frame} -> #{snapshot.frame}"

    radar = prevSnapshot.radar if prevSnapshot.radar

    for id, s of prevSnapshot.data
      if s == null
        delete bodies[id]
        continue

      # Look for new objects in the snapshot and add them to the bodies set
      b = bodies[id]
      unless b
        # Make a new body using the data and add it to the space.
        throw new Error "missing data for #{id}" unless s.model?
        #console.log "adding #{id}"
        b = bodies[id] = s
        b.u or= []

      # Update data for a ship (color, loadout, etc)
      if s.color?
        b.color = s.color
        b.loadout = s.loadout
        b.label = s.label

      #if s.correction
      #  b[k] = s.correction[k] for k in ['x', 'y', 'a', 'dx', 'dy', 'da', 'ddx', 'ddy', 'dda']

  for id, s of snapshot.data when s?.u
    throw new Error 'skipping a u' if bodies[id].u.length
    bodies[id].u = s.u # Object update booster pack!

  prevSnapshot = snapshot

vrotate = (v1, v2) ->
  x: v1.x*v2.x - v1.y*v2.y, y: v1.x*v2.y + v1.y*v2.x

clamp = (x, min, max) -> Math.max(min, Math.min(x, max))

vclamp = (v, len) ->
  l2 = v.x*v.x + v.y*v.y
  return if l2 > len*len
    mul = len / Math.sqrt l2
    {x:mul * v.x, y:mul * v.y}
  else
    v

iterateSimulation = ->
  for id, body of bodies
    #console.log "iterate", body.u.length
    u = body.u.shift()
    #console.log body.a, body.da, body.dda, u?.a
    if u
      body.x = u.x
      body.y = u.y
      body.a = u.a
      if u.dx?
        body.dx = u.dx
        body.dy = u.dy
        body.da = u.da
        body.ddx = u.ddx
        body.ddy = u.ddy
        body.dda = u.dda

    else
      # ddx, ddy are in body coordinates.
      rot = x:Math.cos(body.a), y:Math.sin(body.a)
      dd = vrotate {x:body.ddx, y:body.ddy}, rot
    
      d = x: body.dx + dd.x * fmult, y: body.dy + dd.y * fmult
      d = vclamp d, body.v_limit
      body.dx = d.x
      body.dy = d.y

      body.x += body.dx * fmult
      body.y += body.dy * fmult

      body.da = clamp(body.da + body.dda * fmult, -body.w_limit, body.w_limit)
      body.a += body.da * fmult

    #throw new Error('aa') if Math.abs(body.x) > 3500
    #throw new Error('aa') if Math.abs(body.y) > 3500

  frame++
  dirty = true


update = ->
  # If we get lag of more than one snapshot frame or are disconnected, pause the simulation.
  # This will also happen before the first snapshot frame has been recieved.
  return if frame == prevSnapshot.frame + snapshotDelay and pendingSnapshots.length == 0

  # We've fallen behind.
  while pendingSnapshots.length >= 1 # Increase me to 2 to improve lag tollerance.
    snapshot = pendingSnapshots.shift()
    if frame < snapshot.frame
      console.log "warping #{frame} -> #{snapshot.frame}"
      iterateSimulation() while frame < snapshot.frame
      lastFrameTime = Date.now()
    applySnapshot snapshot

  iterateSimulation()

  if (body = bodies[avatar])
    viewportX = body.x - canvas.width/2
    viewportY = body.y - canvas.height/2

starfield = ({
    x: Math.random()*canvas.width
    y: Math.random()*canvas.height
    d: Math.random()*0.3+0.01
    r: Math.random()*2
    t: Math.random()
} for [1..200])

draw = ->
  return unless dirty # Only draw once despite how many updates have happened
  dirty = false

  #console.log 'draw'
  ctx.fillStyle = 'black'
  ctx.fillRect 0, 0, canvas.width, canvas.height

  for {x, y, d, t} in starfield
    r = d * 6
    #grd = ctx.createRadialGradient x, y, 0, x, y, r
    #grd.addColorStop 0, "hsla(#{Math.max(45,t*90)}, 50%, #{t*100}%, 1)"
    #grd.addColorStop 1, "hsla(#{Math.max(45,t*90)}, 50%, #{t*50}%, 0)"
    #ctx.fillStyle = grd
    ctx.fillStyle = "hsl(#{t*45}, 100%, #{t*50}%)"
    ctx.beginPath()
    x = (x - viewportX * d) % canvas.width
    x += canvas.width if x < 0
    y = (y + viewportY * d) % canvas.height
    y += canvas.height if y < 0
    ctx.arc x, y, r, 0, Math.PI*2
    ctx.fill()

  ctx.save()
  ctx.translate 0, canvas.height
  ctx.scale 1, -1

  ctx.translate -viewportX, -viewportY

  ctx.fillStyle = '#0000cc'
  ctx.fillRect -3000, -3000-10, 6000, 10
  ctx.fillRect -3000-10, -3000, 10, 6000
  ctx.fillRect 3000, -3000, 10, 6000
  ctx.fillRect -3000, 3000, 6000, 10

  cx = viewportX + canvas.width / 2
  cy = viewportY + canvas.height / 2
  radius = Math.min(canvas.width, canvas.height) / 2

  for {x, y, heat} in radar when x < viewportX or x > viewportX + canvas.width or
      y < viewportY or y > viewportY + canvas.height

  
    x = x - cx
    y = y - cy
    m = y/x
    w = canvas.width
    h = canvas.height

    hf = Math.log(Math.E + heat)/6
    #console.log "heat", heat, "hf", hf
    ctx.fillStyle = "hsla(0, #{Math.round(100*hf)}%, 50%, #{hf})"

    if Math.abs(m) > 1
      y = clamp(y, -h/2, h/2)
      x = y / m
    else
      x = clamp(x, -w/2, w/2)
      y = x * m

    #dot = cp.v.mult(cp.v.normalize(vect), radius)
    dot = {x, y}
    dist = cp.v.len dot

    r = 1/Math.log(Math.E + (dist) / 100) * 50
    ctx.beginPath()
    ctx.arc dot.x + cx, dot.y + cy, r, 0, Math.PI*2
    #ctx.arc cx, cy, 100, 0, Math.PI*2
    ctx.fill()

  for id, body of bodies
    ctx.fillStyle = body.color or 'red'
    ctx.lineWidth = 1.5
    ctx.strokeStyle = 'grey'

    ctx.save()
    ctx.translate body.x, body.y
    ctx.rotate body.a
    ctx.beginPath()

    verts = body.model.verts
    len = verts.length
    ctx.moveTo verts[len - 2] + body.model.offset.x, verts[len - 1] + body.model.offset.y
    for i in [0...len] by 2
      ctx.lineTo verts[i] + body.model.offset.x, verts[i+1] + body.model.offset.y

    ctx.fill()
    ctx.stroke()
    ctx.restore()

    if body.label
      ctx.scale 1, -1
      ctx.font = '14px Helvetica'
      ctx.textAlign = 'center'
      ctx.fillText body.label, body.x, -body.y + 50
      ctx.scale 1, -1

  ctx.restore()

avatar = null

runFrame = ->
  nominalTime = lastFrameTime + dt
  actualTime = Date.now()
  setTimeout runFrame, Math.max(0, nominalTime - actualTime + dt)
  lastFrameTime = nominalTime

  update()
  requestAnimationFrame draw if dirty

nextNetSnapshotFrame = 0
ws.onmessage = (msg) ->
  if typeof msg.data is 'string'
    msg = JSON.parse msg.data
    console.log msg.data
  else
    # Binary.
    msg = readPacket msg.data
    return unless msg

    switch msg.type
      when 'snapshot'
        snapshot =
          data: msg.data.data
          radar: msg.data.radar
          frame: nextNetSnapshotFrame
        #console.log "frame #{frame} got snapshot #{snapshot.frame}"
        #console.log snapshot.data
        nextNetSnapshotFrame += snapshotDelay
        pendingSnapshots.push snapshot

        if frame is null
          # This is the first snapshot.
          frame = -delay

      when 'lua message'
        console.log 'ignoring lua message'

      when 'set avatar'
        avatar = msg.data
        console.log 'avatar', msg.data


send = (msg) -> ws.send JSON.stringify msg

rateLimit = (fn) ->
  queuedMessage = false
  ->
    return if queuedMessage
    queuedMessage = true
    setTimeout ->
        queuedMessage = false
        fn()
      , 50

username = if window.location.hash
  window.location.hash.substr(1)
else
  prompt "LOGIN PLOX"
window.location.hash = username

ws.onopen = ->
  ws.send username
  #sendViewportToServer()
  lastFrameTime = Date.now()
  runFrame()

document.onmousewheel = (e) ->
  #console.log "mouse scroll", e
  viewportX -= e.wheelDeltaX
  viewportY += e.wheelDeltaY
  e.preventDefault()

if username is 'seph'
  targetAngle = null
  sendTarget = rateLimit -> ws.send "a #{targetAngle}" if ws.readyState is WebSocket.OPEN

  canvas.onmousemove = (e) ->
    x = e.offsetX - canvas.width / 2
    y = canvas.height / 2 - e.offsetY
    targetAngle = Math.atan2 -x, y
    # Round it a bit to make the message smaller
    targetAngle = Math.floor(targetAngle * 100) / 100
    sendTarget e
    

downKeys = {}

keyEvent = (e, down) ->
  key = String.fromCharCode e.keyCode
  #console.log e.keyCode, key

  m = {'W':'up', 'A':'left', 'S':'down', 'D':'right', ' ':'fire'}
  if m[key]
    e.stopPropagation()
    e.preventDefault()

    # Ignore (debounce!)
    return if down and downKeys[key]

    downKeys[key] = down

    ws.send "#{m[key]} #{if down then 'on' else 'off'}"
    #send {key, down}


document.onkeydown = (e) -> keyEvent e, true
document.onkeyup = (e) -> keyEvent e, false

