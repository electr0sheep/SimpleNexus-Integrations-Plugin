/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * DS205: Consider reworking code to avoid use of IIFEs
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
let LineNumberView;
const {CompositeDisposable} = require('atom');
const {debounce}  = require('lodash');

module.exports =
(LineNumberView = class LineNumberView {
  constructor(editor) {
    this._update = this._update.bind(this);
    this._handleUpdate = this._handleUpdate.bind(this);
    this._updateSync = this._updateSync.bind(this);
    this._undo = this._undo.bind(this);
    this.editor = editor;
    this.subscriptions = new CompositeDisposable();
    this.editorView = atom.views.getView(this.editor);
    this.debounceMotion = atom.config.get('relative-numbers.debounceMotion');
    this.trueNumberCurrentLine = atom.config.get('relative-numbers.trueNumberCurrentLine');
    this.showAbsoluteNumbers = atom.config.get('relative-numbers.showAbsoluteNumbers');
    this.startAtOne = atom.config.get('relative-numbers.startAtOne');
    this.softWrapsCount = atom.config.get('relative-numbers.softWrapsCount');
    this.showAbsoluteNumbersInInsertMode = atom.config.get('relative-numbers.showAbsoluteNumbersInInsertMode');

    this.lineNumberGutterView = atom.views.getView(this.editor.gutterWithName('line-number'));

    this.gutter = this.editor.addGutter({
      name: 'relative-numbers'});
    this.gutter.view = this;

    this._updateDebounce();

    this.inStructure = false
    this.lastTopRow = 0
    this.goingDown = true
    this.pageNumber = 0

    try {
      // Preferred: Subscribe to any editor model changes
      this.subscriptions.add(this.editorView.model.onDidChange(() => {
        return setTimeout(this._update, 0);
      })
      );
    } catch (error) {
      // Fallback: Subscribe to initialization and editor changes
      this.subscriptions.add(this.editorView.onDidAttach(this._update));
      this.subscriptions.add(this.editor.onDidStopChanging(this._update));
    }

    // Subscribe for when the cursor position changes
    this.subscriptions.add(this.editor.onDidChangeCursorPosition(this._update));

    // Update when scrolling
    this.subscriptions.add(this.editorView.onDidChangeScrollTop(this._update));

    // Subscribe to when the revert to absolute numbers config option is modified
    this.subscriptions.add(atom.config.onDidChange('relative-numbers.debounceMotion', () => {
      this.debounceMotion = atom.config.get('relative-numbers.debounceMotion');
      return this._updateDebounce();
    })
    );

    // Subscribe to when the true number on current line config is modified.
    this.subscriptions.add(atom.config.onDidChange('relative-numbers.trueNumberCurrentLine', () => {
      this.trueNumberCurrentLine = atom.config.get('relative-numbers.trueNumberCurrentLine');
      return this._update();
    })
    );

    // Subscribe to when the show absolute numbers setting has changed
    this.subscriptions.add(atom.config.onDidChange('relative-numbers.showAbsoluteNumbers', () => {
      this.showAbsoluteNumbers = atom.config.get('relative-numbers.showAbsoluteNumbers');
      return this._updateAbsoluteNumbers();
    })
    );

    // Subscribe to when the start at one config option is modified
    this.subscriptions.add(atom.config.onDidChange('relative-numbers.startAtOne', () => {
      this.startAtOne = atom.config.get('relative-numbers.startAtOne');
      return this._update();
    })
    );

    // Subscribe to when the start at one config option is modified
    this.subscriptions.add(atom.config.onDidChange('relative-numbers.softWrapsCount', () => {
      this.softWrapsCount = atom.config.get('relative-numbers.softWrapsCount');
      return this._update();
    })
    );

    // Subscribe to when the revert to absolute numbers config option is modified
    this.subscriptions.add(atom.config.onDidChange('relative-numbers.showAbsoluteNumbersInInsertMode', () => {
      this.showAbsoluteNumbersInInsertMode = atom.config.get('relative-numbers.showAbsoluteNumbersInInsertMode');
      return this._updateInsertMode();
    })
    );


    // Dispose the subscriptions when the editor is destroyed.
    this.subscriptions.add(this.editor.onDidDestroy(() => {
      return this.subscriptions.dispose();
    })
    );

    this._update();
    this._updateAbsoluteNumbers();
    this._updateInsertMode();
  }

  destroy() {
    this.subscriptions.dispose();
    this._undo();
    return this.gutter.destroy();
  }

  _spacer(totalLines, currentIndex) {
    const width = Math.max(0, totalLines.toString().length - currentIndex.toString().length);
    return Array(width + 1).join('&nbsp;');
  }

  _spacer2() {
    return Array(9).join('&nbsp;');
  }

  _update() {
    return this.debouncedUpdate();
  }

  // Update the line numbers on the editor
  _handleUpdate() {
    // If the gutter is updated asynchronously, we need to do the same thing
    // otherwise our changes will just get reverted back.
    if (this.editorView.isUpdatedSynchronously()) {
      return this._updateSync();
    } else {
      return atom.views.updateDocument(() => this._updateSync());
    }
  }

  _updateSync() {
    let endOfLineSelected;
    if (this.editor.isDestroyed()) {
      return;
    }
    if (!this.editor.getPath().toUpperCase().endsWith(".JSON")) {
      return
    }

    const totalLines = this.editor.getLineCount();
    let currentLineNumber = this.softWrapsCount ? this.editor.getCursorScreenPosition().row : this.editor.getCursorBufferPosition().row;

    // Check if selection ends with newline
    // (The selection ends with new line because of the package vim-mode when
    // ctrl+v is pressed in visual mode)
    if (this.editor.getSelectedText().match(/\n$/)) {
      endOfLineSelected = true;
    } else {
      currentLineNumber = currentLineNumber + 1;
    }

    const lineNumberElements = this.editorView.querySelectorAll('.line-numbers .line-number');
    const offset = this.startAtOne ? 1 : 0;
    const counting_attribute = this.softWrapsCount ? 'data-screen-row' : 'data-buffer-row';

    return (() => {
      const result = [];
      var firstElement = true
      for (let lineNumberElement of Array.from(lineNumberElements)) {
      // "|| 0" is used given data-screen-row is undefined for the first row
        let dontChange = false
        const row = Number(lineNumberElement.getAttribute(counting_attribute)) || 0;

        const absolute = (Number(lineNumberElement.getAttribute('data-buffer-row')))

        var pageText = "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"
        if (this.editor.lineTextForBufferRow(absolute) == "  \"structure\": [") {
          this.inStructure = true
        } else if (this.editor.lineTextForBufferRow(absolute) == "  ],") {
          this.inStructure = false
        } else if (this.editor.lineTextForBufferRow(absolute) == "    {" && this.inStructure === true && lineNumberElement.innerHTML.search("<span class=\"relative\">") === -1) {
          // if (this.goingDown === true) {
          //   pageNumber++
          // } else {
          //   pageNumber--
          // }
          console.log(lineNumberElement)
          this.pageNumber++
          pageText = `Page ${this.pageNumber} | `
          console.log(this.pageNumber)
        } else if (this.editor.lineTextForBufferRow(absolute) == "    {" && this.inStructure === true && lineNumberElement.innerHTML.search("<span class=\"relative\">") !== -1) {
          dontChange = true
        }

        let relativeClass = 'relative';

        // Keep soft-wrapped lines indicator
        if (dontChange === false) {
          if (lineNumberElement.innerHTML.indexOf('•') === -1) {
            // result.push(lineNumberElement.innerHTML = `${pageText}${this._spacer(totalLines, absolute) + absolute}`)
            result.push(lineNumberElement.innerHTML = `<span class=\"absolute\">${pageText}</span>${this._spacer(totalLines, absolute + 1)}<span class=\"${relativeClass}\">${(absolute + 1)}</span><div class=\"icon-right\"></div>`);
          } else {
            result.push(undefined);
          }
        }
        // if (firstElement) {
        //   console.log(absolute)
        //   // console.log(lineNumberElement.outerHTML)
        //   // console.log(lineNumberElement.outerHTML.match(/<span class=\"relative\">(.*?)<\/span>/))
        //   // console.log(Number(lineNumberElement.outerHTML.match(/<span class=\"relative\">(.*?)<\/span>/)))
        //   // console.log(this.lastTopRow)
        //   if (Number(lineNumberElement.outerHTML.match(/<span class=\"relative\">(.*?)<\/span>/)) >= this.lastTopRow) {
        //     this.goingDown = true
        //   } else {
        //     this.goingDown = false
        //   }
        //   firstElement = false
        // }
        // this.lastTopRow = Number(lineNumberElement.getAttribute(counting_attribute))
        // console.log(this.goingDown)
      }
      return result;
    })();
  }

  _updateAbsoluteNumbers() {
    return this.lineNumberGutterView.classList.toggle('show-absolute', this.showAbsoluteNumbers);
  }

  _updateInsertMode() {
    return this.lineNumberGutterView.classList.toggle('show-absolute-insert-mode', this.showAbsoluteNumbersInInsertMode);
  }

  _updateDebounce() {
    if (this.debounceMotion) {
      return this.debouncedUpdate = debounce(this._handleUpdate, this.debounceMotion, {maxWait: this.debounceMotion});
    } else {
      return this.debouncedUpdate = this._handleUpdate;
    }
  }

  // Undo changes to DOM
  _undo() {
    const totalLines = this.editor.getLineCount();
    const lineNumberElements = this.editorView.querySelectorAll('.line-number');
    for (let lineNumberElement of Array.from(lineNumberElements)) {
      const row = Number(lineNumberElement.getAttribute('data-buffer-row'));
      const absolute = row + 1;
      const absoluteText = this._spacer(totalLines, absolute) + absolute;
      if (lineNumberElement.innerHTML.indexOf('•') === -1) {
        lineNumberElement.innerHTML = `${absoluteText}<div class=\"icon-right\"></div>`;
      }
    }

    this.lineNumberGutterView.classList.remove('show-absolute');
    return this.lineNumberGutterView.classList.remove('show-absolute-insert-mode');
  }
});
