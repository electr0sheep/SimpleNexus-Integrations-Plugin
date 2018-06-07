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
    let selection = editor.getText()
    selection = selection.replace(/({[^}]*)      "min": 0,\n([^}]*)      "max": 0,\n([^}]*})/g, '$1$2$3')
    editor.setText(selection)
  },

  removeDuplicateDescriptions: function () {
    let selection = editor.getText()
    selection = selection.replace(/({[^}]*"title": ")(.*)("[^}]*)      "description": "\2",\n([^}]*})/g, '$1$2$3$4')
    selection = selection.replace(/({[^}]*)      "description": "(.*)",\n([^}]*"title": ")\2("[^}]*})/g, '$1$3$2$4')
    editor.setText(selection)
  },

  removeBlankFields: function () {
    let selection = editor.getText()
    selection = selection.replace(/({[^}]*type": "single_choice"[^}]*"choices": \[\n        )("[^"][^}]*})/g, '$1"",\n        $2')
    editor.setText(selection)
  }

}
