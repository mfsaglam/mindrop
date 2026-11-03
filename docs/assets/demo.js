(() => {
  const keyword = document.getElementById('demo-keyword');
  if (!keyword) return;
  const result = document.getElementById('demo-result');
  const value = document.getElementById('demo-value');
  const label = document.getElementById('demo-label');
  const icon = document.getElementById('demo-icon');
  const pause = document.getElementById('demo-pause');
  const stage = document.querySelector('.demo-stage');
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const examples = [
    { keyword: 'parking', value: 'Level B2 blue zone 147', icon: 'P', color: '#668876' },
    { keyword: 'gym locker', value: '4826', icon: '#', color: '#89749f' },
    { keyword: 'shoe size', value: 'EU 42', icon: '↔', color: '#a27886' },
    { keyword: 'printer ink', value: '305XL black', icon: '▤', color: '#97836c' }
  ];
  let index = 0, character = 0, phase = 'typing', timer, paused = false;
  function showExample() {
    const example = examples[index];
    value.textContent = example.value;
    label.textContent = example.keyword;
    icon.textContent = example.icon;
    icon.style.background = example.color;
    stage.setAttribute('aria-label', `Illustrative Spotlight search: searching ${example.keyword} shows ${example.value}, saved in Mindrop.`);
  }
  function stop() { clearTimeout(timer); }
  function schedule(delay) {
    stop();
    if (!paused && !motion.matches && !document.hidden) timer = setTimeout(tick, delay);
  }
  function tick() {
    const example = examples[index];
    if (phase === 'typing') {
      keyword.textContent = example.keyword.slice(0, ++character);
      if (character >= example.keyword.length) { phase = 'show'; schedule(220); }
      else schedule(115);
    } else if (phase === 'show') {
      result.classList.remove('is-hidden'); phase = 'hold'; schedule(3100);
    } else if (phase === 'hold') {
      result.classList.add('is-hidden'); phase = 'erase'; schedule(300);
    } else {
      keyword.textContent = example.keyword.slice(0, --character);
      if (character <= 0) {
        index = (index + 1) % examples.length;
        showExample(); phase = 'typing'; schedule(550);
      } else schedule(50);
    }
  }
  function renderMode() {
    stop();
    pause.hidden = motion.matches;
    if (motion.matches) {
      index = 0; showExample(); keyword.textContent = examples[0].keyword;
      result.classList.remove('is-hidden');
    } else {
      character = 0; phase = 'typing'; keyword.textContent = '';
      result.classList.add('is-hidden'); schedule(700);
    }
  }
  pause.addEventListener('click', () => {
    paused = !paused;
    pause.textContent = paused ? 'Play animation' : 'Pause animation';
    document.querySelector('.cursor').style.animationPlayState = paused ? 'paused' : 'running';
    if (paused) {
      stop();
      // Keep a readable example on screen even when paused mid-keystroke.
      character = examples[index].keyword.length;
      keyword.textContent = examples[index].keyword;
      result.classList.remove('is-hidden');
      phase = 'hold';
    } else schedule(3100);
  });
  document.addEventListener('visibilitychange', () => { if (document.hidden) stop(); else schedule(400); });
  motion.addEventListener('change', renderMode);
  renderMode();
})();
