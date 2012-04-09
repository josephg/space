cp = require 'chipmunk'

nextId = 0

module.exports = (initialSnapshot) ->
  space = new cp.Space()
  
  for i in [0...100]
    width = 50
    height = 50
    mass = Math.random() * 100

    body = space.addBody new cp.Body(mass, cp.momentForBox(mass, width, height))
    body.setPos cp.v(Math.floor(i/10) * 100, (i % 10) * 100)
    body.w = Math.random() * 3 - 1.5
    space.addShape new cp.BoxShape(body, width, height)
    body.id = nextId++
    body.vx = Math.random() * 10 - 5
    body.vy = Math.random() * 10 - 5

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

  snapshot: (knownObjects, x, y, width, height) ->
    bodies = {}

    space.bbQuery {l:x, r:x+width, b:y, t:y+height}, cp.ALL_LAYERS, cp.NO_GROUP, (shape) ->
      bodies[shape.body.id] = shape.body


    snapshot = {}
    for id, b of bodies
      snapshot[id] =
        #id:b.id
        a:b.a # angle
        x:b.p.x # Position
        y:b.p.y
        vx:b.vx # Velocity
        vy:b.vy
        w:b.w # angular momentum
        fx:b.f.x # Force
        fy:b.f.y
        t:b.t # torque

      unless knownObjects[id]
        snapshot[id].m = b.m # Mass
        snapshot[id].i = b.i # Moment
        snapshot[id].shapes = (s.verts for s in b.shapeList)
        knownObjects[id] = b

    snapshot
    


