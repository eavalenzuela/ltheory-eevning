// Helpers for the mock-up pages: line icons of our own, the dock, a window's frame.
const ICONS = {
  inventory: '<path d="M4 8l8-4 8 4v8l-8 4-8-4z"/><path d="M4 8l8 4 8-4M12 12v8"/>',
  market: '<path d="M3 20h18M6 20v-7M10.5 20V6M15 20v-9M19.5 20V9"/>',
  fitting: '<circle cx="12" cy="12" r="7"/><path d="M12 2.5v4M12 17.5v4M2.5 12h4M17.5 12h4"/><circle cx="12" cy="12" r="1.6"/>',
  ships: '<path d="M12 3l6 17-6-4-6 4z"/>',
  industry: '<path d="M3 20V11l5 3v-3l5 3V5h6v15zM3 20h18"/>',
  skills: '<path d="M5 5h10a3 3 0 0 1 3 3v12H8a3 3 0 0 1-3-3z"/><path d="M5 17a3 3 0 0 1 3-3h10M9 9h5"/>',
  jobs: '<path d="M7 5h10v15H7z"/><path d="M9.5 3.500h5v3h-5zM10 11h4M10 14h4M10 17h2"/>',
  wallet: '<ellipse cx="12" cy="7" rx="7" ry="3"/><path d="M5 7v5c0 1.700 3.100 3 7 3s7-1.300 7-3V7M5 12v5c0 1.700 3.100 3 7 3s7-1.300 7-3v-5"/>',
  crew: '<circle cx="12" cy="8" r="3.500"/><path d="M5 20c0-3.900 3.100-6 7-6s7 2.100 7 6"/>',
  corporation: '<path d="M5 20V7l7-3.500L19 7v13M3 20h18M9 10h2M13 10h2M9 14h2M13 14h2M10.500 20v-3h3v3"/>',
  map: '<circle cx="5.500" cy="6.500" r="1.800"/><circle cx="18" cy="9" r="1.800"/><circle cx="9" cy="18" r="1.800"/><circle cx="17.500" cy="18.500" r="1.200"/><path d="M7.200 7l9 1.700M6 8.200l2.500 8M10.300 16.700l6.500-6.300M10.800 18.200l5.500.2"/>',
  scanner: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="4"/><path d="M12 12l5.600-5.600"/><circle cx="15.500" cy="14.500" r="0.900" fill="currentColor"/>',
  events: '<path d="M6 16v-5a6 6 0 0 1 12 0v5l2 2H4z"/><path d="M10 20.500a2 2 0 0 0 4 0"/>',
  colonies: '<circle cx="12" cy="12" r="5.500"/><path d="M3.500 15c2.500 1.500 14.500-4.500 17-7.500"/>',
  guide: '<circle cx="12" cy="12" r="8"/><path d="M9.700 9.700a2.400 2.400 0 1 1 3.400 2.200c-.7.400-1.100.900-1.100 1.800M12 16.600v.200"/>',
  menu: '<path d="M5 7h14M5 12h14M5 17h14"/>',
  fleet: '<path d="M12 4l4 10-4-2.500L8 14zM5.500 12l2.500 7-2.500-1.600L3 19zM18.500 12l2.500 7-2.500-1.600L16 19z"/>',
  close: '<path d="M7 7l10 10M17 7L7 17"/>',
  pin: '<path d="M9 4h6l-1 6 3 3H7l3-3zM12 13v7"/>',
  search: '<circle cx="10.500" cy="10.500" r="5.500"/><path d="M15 15l5 5"/>',
  right: '<path d="M9 6l6 6-6 6"/>',
  down: '<path d="M6 9l6 6 6-6"/>',
  up: '<path d="M6 15l6-6 6 6"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.600 5.600l2.100 2.100M16.300 16.300l2.100 2.100M5.600 18.400l2.100-2.100M16.300 7.700l2.100-2.100"/>',
  pause: '<path d="M8 6v12M16 6v12"/>',
  info: '<circle cx="12" cy="12" r="8"/><path d="M12 11v6M12 7.500v.300"/>',
  lock: '<path d="M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5"/><circle cx="12" cy="12" r="1.500" fill="currentColor"/>',
  // what a thing is, on its row
  gun: '<path d="M4 15h7v-5H4zM11 12.500h9M6 15v3"/>',
  laser: '<path d="M4 15h6v-5H4zM10 12.500h4M16 12.500h1M19 12.500h1"/>',
  missile: '<path d="M4 12h11l4-2.500V14.500L15 12M4 9.500V14.500"/>',
  shield: '<path d="M12 4l7 3v5c0 4-3 6.500-7 8-4-1.500-7-4-7-8V7z"/>',
  plate: '<path d="M5 7h14M5 12h14M5 17h14"/>',
  engine: '<path d="M5 8h8l5 4-5 4H5zM2 10.500h3M2 13.500h3"/>',
  module: '<circle cx="12" cy="12" r="4"/><path d="M12 4v3M12 17v3M4 12h3M17 12h3"/>',
  round: '<path d="M9 20V10c0-3 1.500-5 3-6 1.500 1 3 3 3 6v10z"/>',
  ore: '<path d="M8 5h8l4 7-4 7H8l-4-7z"/>',
  bar: '<path d="M7 9h10l3 7H4z"/>',
  ship: '<path d="M4 12l15-6-3 6 3 6z"/>',
  print: '<path d="M5 5h14v14H5zM5 10h14M5 14.500h14M10 5v14M14.500 5v14"/>',
  book: '<path d="M6 4h12v16H6zM9 4v16M12 8h3"/>',
  drone: '<path d="M12 8v8M8 12h8"/><circle cx="12" cy="12" r="6.500"/>',
  station: '<path d="M12 3v18M7 7h10M5 12h14M8 17h8"/>',
  gate: '<circle cx="12" cy="12" r="7.500"/><circle cx="12" cy="12" r="3"/>',
  planet: '<circle cx="12" cy="12" r="7"/>',
  wreck: '<path d="M5 18l4-10 3 5 3-8 4 13"/>',
  belt: '<path d="M6 8l3-2 3 2-1 3-4 .500zM14 14l3-1 2 3-2 3-3-1z"/>',
  site: '<path d="M12 4l8 14H4z"/>',
  battery: '<path d="M6 19v-6h12v6M9 13V8h6v5M12 8V4"/>',
};
function ic(name, size = 16, width = 1.6) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${width}" stroke-linecap="square" stroke-linejoin="miter">${ICONS[name] || ''}</svg>`;
}
function ii(name, cls = '') { return `<span class="ii ${cls}">${ic(name, 15, 1.7)}</span>`; }
function put(html) { document.body.insertAdjacentHTML('beforeend', html); }

// The dock. 'open': windows that are open; 'off': not to be had here (a station's own, in space);
// 'hot': the one the cursor is on (its name is shown beside it).
const DOCK = [
  ['inventory', 'Inventory', 'I'], ['fitting', 'Fitting', ''], ['ships', 'Ships', ''], ['market', 'Market', ''],
  ['industry', 'Industry', ''], ['jobs', 'Jobs', 'J'], '-',
  ['skills', 'Skills', ''], ['wallet', 'Wallet', ''], ['crew', 'Crew and fleet', ''], ['corporation', 'Corporation', ''], '-',
  ['map', 'Star map', 'M'], ['scanner', 'Scanner', ''], ['colonies', 'Colonies', ''], ['events', 'Events', ''], '-',
  ['guide', 'Guide', ''], ['menu', 'Menu', 'Esc'],
];
function dock(o = {}) {
  let y = 8, tip = '';
  const out = DOCK.map(e => {
    if (e === '-') { y += 13; return '<div class="sep"></div>'; }
    const [id, name, key] = e;
    const cls = [(o.open || []).includes(id) ? 'open' : '', (o.off || []).includes(id) ? 'off' : '', o.hot === id ? 'hot' : ''].join(' ');
    const badge = o.badge && o.badge[id] ? `<span class="badge">${o.badge[id]}</span>` : '';
    if (o.hot === id) {
      tip = `<div class="tip" style="left:58px;top:${y + 6}px">${name}${key ? `<span class="k">${key}</span>` : ''}${o.hotNote ? `<div class="t2">${o.hotNote}</div>` : ''}</div>`;
    }
    y += 44;
    return `<div class="b ${cls}">${ic(id, 24, 1.5)}${badge}</div>`;
  }).join('');
  put(`<div class="dock">${out}<div class="clock"><div class="c">${ic('pause', 14, 2)}</div><div class="x">x1</div><div class="c">- &nbsp;+</div></div></div>${tip}`);
}
function where(o) {
  put(`<div class="where" style="border-left-color:var(--${o.tone || 'good'})"><div class="sys">${o.system}</div>
    <div class="l"><span class="pill ${o.tone || 'good'}">${o.security}</span><span class="warn b5">${o.owner}</span><span class="dim">${o.region}</span></div>
    <div class="l"><span>${o.at}</span></div>
    <div class="l"><span class="dim">${o.ship}</span><span class="sp"></span><span class="b6">${o.wallet} cr</span></div></div>`);
}
function win(o, body) {
  return `<div class="win ${o.focus ? 'focus' : ''}" style="left:${o.x}px;top:${o.y}px;width:${o.w}px;height:${o.h}px">
    <div class="bar"><span class="wi">${ic(o.icon, 16, 1.7)}</span><span class="title">${o.title}</span><span class="sub">${o.sub || ''}</span><span class="sp"></span>
      <span class="ctl"><span>${ic('pin', 14, 1.6)}</span><span>${ic('close', 14, 1.8)}</span></span></div>${body}<div class="grip"></div></div>`;
}
function chev(open) { return `<span class="c">${ic(open ? 'down' : 'right', 11, 2.2)}</span>`; }
