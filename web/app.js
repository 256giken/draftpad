const LANGS = ['markdown', 'plaintext', 'yaml', 'bat', 'html', 'xml', 'dockerfile', 'javascript', 'typescript',
  'ruby', 'go', 'css', 'less', 'scss', 'sol', 'mysql', 'pgsql', 'php', 'powershell', 'rust'];
const init = window.__draftpad;
const post = (msg) => window.webkit.messageHandlers.draftpad.postMessage(msg);
const dark = window.matchMedia('(prefers-color-scheme: dark)');

self.MonacoEnvironment = {
  getWorkerUrl: () => 'data:text/javascript;charset=utf-8,' + encodeURIComponent(
    `self.MonacoEnvironment={baseUrl:'draftpad://app/'};importScripts('draftpad://app/vs/base/worker/workerMain.js');`),
};

const THEMES = {
  'solarized-light': { base: 'vs', bg: '#fdf6e3', fg: '#657b83', line: '#eee8d5', sel: '#eee8d5', cursor: '#657b83',
    comment: '93a1a1', keyword: '859900', string: '2aa198', number: 'd33682', type: 'b58900', delim: '657b83',
    heading: 'cb4b16', link: '268bd2' },
  'solarized-dark': { base: 'vs-dark', bg: '#002b36', fg: '#839496', line: '#073642', sel: '#274642', cursor: '#839496',
    comment: '586e75', keyword: '859900', string: '2aa198', number: 'd33682', type: 'b58900', delim: '839496',
    heading: 'cb4b16', link: '268bd2' },
  'github-light': { base: 'vs', bg: '#ffffff', fg: '#24292f', line: '#f6f8fa', sel: '#b6d7ff', cursor: '#24292f',
    comment: '6e7781', keyword: 'cf222e', string: '0a3069', number: '0550ae', type: '953800', delim: '24292f',
    heading: '0550ae', link: '0a3069' },
  monokai: { base: 'vs-dark', bg: '#272822', fg: '#f8f8f2', line: '#3e3d32', sel: '#49483e', cursor: '#f8f8f0',
    comment: '75715e', keyword: 'f92672', string: 'e6db74', number: 'ae81ff', type: '66d9ef', delim: 'f8f8f2',
    heading: 'a6e22e', link: '66d9ef' },
};

const BUILTIN = { vs: ['#fffffe', '#000000'], 'vs-dark': ['#1e1e1e', '#d4d4d4'], 'hc-light': ['#ffffff', '#292929'], 'hc-black': ['#000000', '#ffffff'] };
const first = THEMES[init.theme] ? [THEMES[init.theme].bg, THEMES[init.theme].fg] : BUILTIN[init.theme];
if (first) {
  document.documentElement.style.setProperty('--bg', first[0]);
  document.documentElement.style.setProperty('--fg', first[1]);
}

require.config({ paths: { vs: 'draftpad://app/vs' } });
require(['vs/editor/editor.main'], () => {
  for (const [name, t] of Object.entries(THEMES)) {
    monaco.editor.defineTheme(name, {
      base: t.base, inherit: true,
      rules: [
        { token: 'comment', foreground: t.comment, fontStyle: 'italic' },
        { token: 'keyword', foreground: t.keyword },
        { token: 'string', foreground: t.string },
        { token: 'number', foreground: t.number },
        { token: 'type', foreground: t.type },
        { token: 'delimiter', foreground: t.delim },
        { token: 'keyword.md', foreground: t.heading },
        { token: 'string.link.md', foreground: t.link },
        { token: 'strong', fontStyle: 'bold' },
        { token: 'emphasis', fontStyle: 'italic' },
      ],
      colors: {
        'editor.background': t.bg, 'editor.foreground': t.fg, 'editor.lineHighlightBackground': t.line,
        'editor.selectionBackground': t.sel, 'editorCursor.foreground': t.cursor,
      },
    });
  }
  const sel = document.getElementById('lang');
  for (const l of LANGS) sel.add(new Option(l, l));
  const language = LANGS.includes(init.language) ? init.language : 'markdown';
  sel.value = language;

  const editor = monaco.editor.create(document.getElementById('editor'), {
    value: init.text,
    language,
    lineNumbers: 'off',
    wordWrap: 'on',
    minimap: { enabled: false },
    automaticLayout: true,
    lineDecorationsWidth: 0,
    autoIndent: 'full',
    quickSuggestions: true,
    tabSize: 4,
    fontSize: init.fontSize,
    copyWithSyntaxHighlighting: false,
  });
  const model = editor.getModel();

  // While composing, WebKit scrolls the visible IME textarea to reveal the caret (3px off Monaco's own
  // scrollTop), so the marked text jumps up and down on every keystroke. Put it back before it paints.
  const ime = editor.getDomNode().querySelector('textarea.inputarea');
  ime.addEventListener('scroll', () => {
    if (!ime.classList.contains('ime-input')) return;
    const rows = ime.value.slice(0, ime.selectionStart).split('\n').length - 1;
    const top = rows * editor.getOption(monaco.editor.EditorOption.lineHeight);
    if (ime.scrollTop !== top) ime.scrollTop = top;
  });

  const updateStatus = () => {
    document.getElementById('chars').textContent = Array.from(model.getValue()).length + ' chars';
    document.getElementById('lines').textContent = model.getLineCount() + ' lines';
  };
  updateStatus();
  model.onDidChangeContent(() => {
    updateStatus();
    post({ type: 'text', text: model.getValue() });
  });

  sel.addEventListener('change', () => {
    monaco.editor.setModelLanguage(model, sel.value);
    post({ type: 'language', language: sel.value });
  });
  let theme = init.theme;
  const applyTheme = () => {
    const name = theme === 'auto' ? (dark.matches ? 'vs-dark' : 'vs') : theme;
    monaco.editor.setTheme(name);
    const cs = getComputedStyle(document.querySelector('.monaco-editor'));
    const root = document.documentElement.style;
    root.setProperty('--bg', cs.backgroundColor);
    root.setProperty('--fg', cs.color);
    const base = THEMES[name]?.base ?? name;
    document.documentElement.style.colorScheme = base === 'vs-dark' || base === 'hc-black' ? 'dark' : 'light';
  };
  applyTheme();
  dark.addEventListener('change', applyTheme);

  window.draftpad = {
    setTheme: (t) => { theme = t; applyTheme(); },
    setFontSize: (n) => editor.updateOptions({ fontSize: n }),
    focus: () => editor.focus(),
    trigger: (id) => { editor.focus(); editor.trigger('menu', id, null); },
  };
  editor.focus();
});
