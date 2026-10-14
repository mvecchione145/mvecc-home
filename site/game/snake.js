// Snake on a square grid. Colors come from the site's CSS variables, so the
// board follows light and dark mode like every other page.
//   Arrow keys / WASD or swipe to steer. Space or tap to pause.

(function () {
  var GRID = 20
  var START_STEP_MS = 140
  var MIN_STEP_MS = 70
  var SPEEDUP_MS = 3
  var SWIPE_MIN_PX = 24
  var BEST_KEY = 'snake-best'

  var DIRS = {
    up: { x: 0, y: -1 },
    down: { x: 0, y: 1 },
    left: { x: -1, y: 0 },
    right: { x: 1, y: 0 },
  }

  var KEYS = {
    ArrowUp: 'up', w: 'up', W: 'up',
    ArrowDown: 'down', s: 'down', S: 'down',
    ArrowLeft: 'left', a: 'left', A: 'left',
    ArrowRight: 'right', d: 'right', D: 'right',
  }

  var canvas = document.getElementById('board')
  var ctx = canvas.getContext('2d')
  var scoreEl = document.getElementById('score')
  var bestEl = document.getElementById('best')
  var messageEl = document.getElementById('message')

  // 'ready' before the first move, then 'playing', 'paused' or 'over'.
  var state = 'ready'
  var snake, dir, turns, food, score, stepMs
  var elapsed = 0
  var lastTime = 0
  var colors = {}
  var best = readBest()

  // Storage can be missing or throw (private windows, blocked site data);
  // the game still works, it just forgets the best score.
  function readBest() {
    try {
      return parseInt(localStorage.getItem(BEST_KEY), 10) || 0
    } catch (e) {
      return 0
    }
  }

  function saveBest() {
    try {
      localStorage.setItem(BEST_KEY, String(best))
    } catch (e) {}
  }

  function readColors() {
    var style = getComputedStyle(document.documentElement)
    colors = {
      bg: style.getPropertyValue('--bg').trim(),
      fg: style.getPropertyValue('--fg').trim(),
      muted: style.getPropertyValue('--muted').trim(),
      rule: style.getPropertyValue('--rule').trim(),
      accent: style.getPropertyValue('--accent').trim(),
    }
  }

  function reset() {
    var mid = Math.floor(GRID / 2)
    snake = [{ x: mid, y: mid }, { x: mid - 1, y: mid }, { x: mid - 2, y: mid }]
    dir = DIRS.right
    turns = []
    score = 0
    stepMs = START_STEP_MS
    elapsed = 0
    food = placeFood()
    updateScore()
  }

  function onSnake(x, y) {
    return snake.some(function (part) {
      return part.x === x && part.y === y
    })
  }

  function placeFood() {
    var free = []
    for (var y = 0; y < GRID; y++) {
      for (var x = 0; x < GRID; x++) {
        if (!onSnake(x, y)) free.push({ x: x, y: y })
      }
    }
    return free.length ? free[Math.floor(Math.random() * free.length)] : null
  }

  // Turns are queued so two quick presses between steps both count, but a
  // turn straight back into the snake's own neck is ignored.
  function turn(name) {
    var next = DIRS[name]
    var last = turns.length ? turns[turns.length - 1] : dir
    if (next === last || (next.x === -last.x && next.y === -last.y)) return
    if (turns.length < 2) turns.push(next)
  }

  function step() {
    if (turns.length) dir = turns.shift()

    var head = { x: snake[0].x + dir.x, y: snake[0].y + dir.y }
    var eating = head.x === food.x && head.y === food.y

    // The tail moves out of the way this step unless the snake is growing,
    // so following your own tail closely is allowed.
    var body = eating ? snake : snake.slice(0, -1)
    var hitWall = head.x < 0 || head.y < 0 || head.x >= GRID || head.y >= GRID
    var hitSelf = body.some(function (part) {
      return part.x === head.x && part.y === head.y
    })
    if (hitWall || hitSelf) return end('Game over.')

    snake.unshift(head)
    if (!eating) {
      snake.pop()
      return
    }

    score++
    stepMs = Math.max(MIN_STEP_MS, stepMs - SPEEDUP_MS)
    updateScore()
    food = placeFood()
    if (!food) end('You filled the board.')
  }

  function updateScore() {
    if (score > best) {
      best = score
      saveBest()
    }
    scoreEl.textContent = score
    bestEl.textContent = best
  }

  function setState(next, message) {
    state = next
    messageEl.textContent = message
  }

  function play() {
    if (state === 'over') reset()
    elapsed = 0
    setState('playing', '')
  }

  function pause() {
    setState('paused', 'Paused. Press space or tap the board to resume.')
  }

  function end(reason) {
    setState('over', reason + ' Press space or tap the board to play again.')
  }

  function togglePause() {
    if (state === 'playing') pause()
    else play()
  }

  function steer(name) {
    if (state === 'paused') return
    if (state !== 'playing') play()
    turn(name)
  }

  document.addEventListener('keydown', function (event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return

    var name = KEYS[event.key]
    if (name) {
      event.preventDefault()
      steer(name)
    } else if (event.key === ' ' || event.key === 'Escape' || event.key === 'p') {
      event.preventDefault()
      togglePause()
    }
  })

  // One handler for mouse, pen and touch: a short press is a tap, a longer
  // drag is a swipe in its strongest direction.
  var pressStart = null

  canvas.addEventListener('pointerdown', function (event) {
    pressStart = { x: event.clientX, y: event.clientY }
  })

  canvas.addEventListener('pointerup', function (event) {
    if (!pressStart) return
    var dx = event.clientX - pressStart.x
    var dy = event.clientY - pressStart.y
    pressStart = null

    if (Math.max(Math.abs(dx), Math.abs(dy)) < SWIPE_MIN_PX) return togglePause()
    if (Math.abs(dx) > Math.abs(dy)) steer(dx > 0 ? 'right' : 'left')
    else steer(dy > 0 ? 'down' : 'up')
  })

  canvas.addEventListener('pointercancel', function () {
    pressStart = null
  })

  document.addEventListener('visibilitychange', function () {
    if (document.hidden && state === 'playing') pause()
  })

  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', readColors)
  window.addEventListener('resize', resize)

  // Size the drawing surface in device pixels, rounded so every cell is a
  // whole number of pixels and edges stay crisp.
  function resize() {
    var ratio = window.devicePixelRatio || 1
    var cell = Math.max(1, Math.floor((canvas.clientWidth * ratio) / GRID))
    canvas.width = canvas.height = cell * GRID
  }

  function block(x, y, cell, inset, color) {
    var size = cell - inset * 2
    ctx.fillStyle = color
    ctx.beginPath()
    if (ctx.roundRect) ctx.roundRect(x * cell + inset, y * cell + inset, size, size, size * 0.25)
    else ctx.rect(x * cell + inset, y * cell + inset, size, size)
    ctx.fill()
  }

  function draw() {
    var cell = canvas.width / GRID
    var inset = Math.max(1, Math.round(cell * 0.08))

    ctx.fillStyle = colors.bg
    ctx.fillRect(0, 0, canvas.width, canvas.height)

    if (food) {
      ctx.fillStyle = colors.accent
      ctx.beginPath()
      ctx.arc((food.x + 0.5) * cell, (food.y + 0.5) * cell, cell * 0.32, 0, Math.PI * 2)
      ctx.fill()
    }

    var body = state === 'over' ? colors.muted : colors.fg
    for (var i = snake.length - 1; i >= 0; i--) {
      block(snake[i].x, snake[i].y, cell, inset, i === 0 && state === 'over' ? colors.accent : body)
    }
  }

  function frame(time) {
    if (state === 'playing') {
      // Cap the catch-up so a slow frame can't run several steps at once.
      elapsed = Math.min(elapsed + (time - lastTime), stepMs * 2)
      while (elapsed >= stepMs && state === 'playing') {
        elapsed -= stepMs
        step()
      }
    }
    lastTime = time
    draw()
    requestAnimationFrame(frame)
  }

  readColors()
  resize()
  reset()
  setState('ready', 'Press an arrow key or swipe on the board to start.')
  requestAnimationFrame(function (time) {
    lastTime = time
    frame(time)
  })
})()
