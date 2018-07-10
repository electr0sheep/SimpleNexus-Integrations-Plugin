module.exports = {
  addCondition: function () {
    let editor = atom.workspace.getActiveTextEditor()

    if (editor) {
      let selection = editor.getText()
      let pos = editor.getBuffer().characterIndexForPosition(editor.getCursorBufferPosition())

      try {
        var parsedJson = JSON.parse(editor.getText())
      }
      catch(err) {
        if (String(err).startsWith("SyntaxError: Unexpected token = in JSON")) {
          atom.notifications.addError("Couldn't parse JSON")
          atom.notifications.addError("It looks like you forgot to clean up extra fields after beautifying!")
        } else {
          atom.notifications.addError("Couldn't parse JSON")
          atom.notifications.addError(String(err))
          atom.notifications.addError("Check console for more information")
          console.error(err)
        }
        return
      }

      // go back until we find a {
      while (selection[pos] != "{" && pos >= 0) {
        pos--
      }
      // go forward until we find a key
      while (selection.substring(pos, pos+3) != "key" && pos < selection.length) {
        pos++
      }

      var index1 = pos + 7
      pos += 7

      while (selection[pos] != "\"" && pos < selection.length) {
        pos++
      }

      var modalPanel;
      // Create root element
      this.element = document.createElement('div');
      this.element.classList.add('SimpleNexus-Integrations-Plugin');

      const conditionDiv = document.createElement('div')

      const fieldSelect = document.createElement('select')
      var options = []
      parsedJson.fields.forEach(function(value,i) {
        options[i] = document.createElement('option')
        options[i].text = value.key
      })
      for (var element of options) {
        fieldSelect.add(element)
      }

      fieldSelect.value = selection.substring(index1, pos)

      conditionDiv.appendChild(fieldSelect)

      // Create button element
      const button = document.createElement('btn');
      button.style.marginTop = "20px";
      button.textContent = 'Okay';
      button.classList.add('btn');
      button.classList.add('btn-lg')
      button.classList.add('btn-primary');
      button.onclick = function () {
        modalPanel.destroy();
      }
      this.element.appendChild(conditionDiv);
      this.element.appendChild(button);

      modalPanel = atom.workspace.addModalPanel({
        item: this.element,
        visible: false
      });
      modalPanel.show();
    }
  }
}
