//TODO: Stephen was running into some issues

const fs = require('fs')

module.exports = {
  insertSimpleNexusTextFromFile: function (path, successNotificationText) {
    if (typeof path != 'string' || typeof successNotificationText != 'string') {
      throw "function insertSimpleNexusTextFromFile takes 2 string parameters"
    }

    let editor
    if (editor = atom.workspace.getActiveTextEditor()) {
      if (editor.getPath() != null) {
        if (editor.getPath().substr(editor.getPath().lastIndexOf('.') + 1).toLowerCase() != path.substr(path.lastIndexOf('.') + 1).toLowerCase()) {
          askFileExtensionDialog(path, editor, successNotificationText)
        } else {
          checkForBlankFile(path, editor, successNotificationText)
        }
      } else {
        atom.notifications.addError("Editor didn't have a path!")
      }
    }
  }
};

function askFileExtensionDialog(path, editor, successNotificationText) {
  let myFirstPromise = new Promise((resolve, reject) => {
    if (atom.config.get("sn-integrations-plugin.showConfirmationDialog")) {
      atom.confirm({
        type: 'warning',
        message: 'Confirm file over-write?',
        detail: 'It looks like the file you are trying to replace doesn\'t have the same extension. Are you sure you want to over-write it?',
        buttons: ['Yes', 'Cancel'],
        checkboxLabel: 'Never ask me again',
        checkboxChecked: false
      }, (response, checkboxChecked) => {
        if (response === 1) {
          return
        }
        if (checkboxChecked) {
          atom.config.set("sn-integrations-plugin.showConfirmationDialog", false)
        }
        resolve()
      })
    }
  })
  myFirstPromise.then(() => {
    checkForBlankFile(path, editor, successNotificationText)
  })
}

function checkForBlankFile(path, editor, successNotificationText) {
  if (editor.getText().length > 0) {
    if (atom.config.get("sn-integrations-plugin.showConfirmationDialog")) {
      atom.confirm({
        type: 'warning',
        message: 'Confirm file over-write?',
        detail: 'It looks like the file you are trying to replace already has content. Are you sure you want to over-write it?',
        buttons: ['Yes', 'Cancel'],
        checkboxLabel: 'Never ask me again',
        checkboxChecked: false
      }, (response, checkboxChecked) => {
        if (response === 1) {
          return
        }
        if (checkboxChecked) {
          atom.config.set("sn-integrations-plugin.showConfirmationDialog", false)
        }
        replaceContents(path, editor, successNotificationText)
      })
    }
  } else {
    replaceContents(path, editor, successNotificationText)
  }
}

function replaceContents(path, editor, successNotificationText) {
  try {
    let data = fs.readFileSync(path)
    editor.setText(data.toString())
    atom.notifications.addSuccess(successNotificationText + " successfully generated!")
  }
  catch(err) {
    atom.notifications.addError(err)
  }
}
