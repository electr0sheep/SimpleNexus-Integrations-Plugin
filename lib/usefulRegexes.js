module.exports = {

  addBlankOptionToSingleChoice: function () {
    let editor
    if (editor = atom.workspace.getActiveTextEditor()) {
      let selection = editor.getText()
      selection = selection.replace(/({[^}]*type": "single_choice"[^}]*"choices": \[\n        )("[^"][^}]*})/g, '$1"",\n        $2')
      selection = selection.replace(/({[^}]*"choices": \[\n        )("[^"][^}]*type": "single_choice"[^}]*})/g, '$1"",\n        $2')
      editor.setText(selection)
    }
  },

  removeMinMaxWhenZero: function () {
    let editor
    if (editor = atom.workspace.getActiveTextEditor()) {
      let selection = editor.getText()
      selection = selection.replace(/({[^}]*)      "min": 0,\n([^}]*)      "max": 0,\n([^}]*})/g, '$1$2$3')
      selection = selection.replace(/({[^}]*)      "max": 0,\n([^}]*)      "min": 0,\n([^}]*})/g, '$1$2$3')
      selection = selection.replace(/({[^}]*)      "min": 0,\n([^}]*),(\n)      "max": 0\n([^}]*})/g, '$1$2$3$4')
      selection = selection.replace(/({[^}]*)      "max": 0,\n([^}]*),(\n)      "min": 0\n([^}]*})/g, '$1$2$3$4')
      editor.setText(selection)
    }
  },

  removeDuplicateDescriptions: function () {
    let editor
    if (editor = atom.workspace.getActiveTextEditor()) {
      let selection = editor.getText()
      selection = selection.replace(/({[^}]*"title": ")(.*)("[^}]*)      "description": "\2",\n([^}]*})/g, '$1$2$3$4')
      selection = selection.replace(/({[^}]*)      "description": "(.*)",\n([^}]*"title": ")\2("[^}]*})/g, '$1$3$2$4')
      selection = selection.replace(/({[^}]*"title": ")(.*)("[^}]*),(\n)      "description": "\2"\n([^}]*})/g, '$1$2$3$4$5')
      editor.setText(selection)
    }
  },

  removeBlankFields: function () {
    let editor
    if (editor = atom.workspace.getActiveTextEditor()) {
      let selection = editor.getText()
      selection = selection.replace(/({[^}]*)      "title": "",\n([^}]*})/g, '$1$2')
      selection = selection.replace(/({[^}]*)      "min": "",\n([^}]*})/g, '$1$2')
      selection = selection.replace(/({[^}]*)      "max": "",\n([^}]*})/g, '$1$2')
      selection = selection.replace(/({[^}]*)      "allowAllStates": "",\n([^}]*})/g, '$1$2')
      selection = selection.replace(/({[^}]*)      "description": "",\n([^}]*})/g, '$1$2')
      selection = selection.replace(/({[^}]*)      "choices": "",\n([^}]*})/g, '$1$2')
      selection = selection.replace(/({[^}]*)      "key": "",\n([^}]*})/g, '$1$2')
      selection = selection.replace(/({[^}]*)      "type": "",\n([^}]*})/g, '$1$2')
      editor.setText(selection)
    }
  }

}
