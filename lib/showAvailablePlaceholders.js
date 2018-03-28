'use babel';

const fs = require('fs')

const showModal = require('./showModal')

module.exports = {
  showAvailablePlaceholders: function () {
    // var placeholderBuilderString = ""
    var placeholderSet = new Set()
    var data
    var dataString
    var regex
    var result

    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/util_replace_placeholders_spec.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open util_replace_placeholders_spec.rb")
      atom.notifications.addError(err.toString())
      return
    }
    // placeholderBuilderString += "<h1>util_replace_placeholders_spec.rb</h1>"
    dataString = data.toString()
    regex = /it \"\[(.*)\]\" do/g
    result = regex.exec(dataString)
    while (result != null) {
      placeholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, ''))
      result = regex.exec(dataString)
    }
    // placeholderBuilderString += (Array.from(placeholderSet).sort().toString().replace(/,/g, '<br>'))
    // placeholderBuilderString += "<br><br><br><br><br><br><br><br>"

    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/user_loan_app.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open user_loan_app.rb")
      atom.notifications.addError(err.toString())
      return
    }
    // placeholderBuilderString += "<h1>user_loan_app.rb</h1>"
    dataString = data.toString()
    regex = /if values\[(.*?)\]/g
    result = regex.exec(dataString)
    while (result != null) {
      placeholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, ''))
      result = regex.exec(dataString)
    }
    // placeholderBuilderString += (Array.from(placeholderSet).sort().toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/,/g, '<br>'))
    // placeholderBuilderString += "<br><br><br><br><br><br><br><br>"

    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/custom_form.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open custom_form.rb")
      atom.notifications.addError(err.toString())
      return
    }
    // placeholderBuilderString += "<h1>custom_form.rb</h1>"
    dataString = data.toString()
    regex = /set_value form_def, (.*), loan./g
    result = regex.exec(dataString)
    while (result != null) {
      placeholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, ''))
      result = regex.exec(dataString)
    }
    // placeholderBuilderString += (Array.from(placeholderSet).sort().toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/,/g, '<br>'))

    // remove bogus entries (maybe I should do this via modified regexp)
    placeholderSet.forEach(function(item){
      if (item.toString().includes("+")) {
        placeholderSet.delete(item)
      } else if (item.toString().includes("CUSTOM_")) {
        placeholderSet.delete(item)
      }
    });

    showModal.displayModal(Array.from(placeholderSet).sort().toString().replace(/,/g, '<br>'))
  }
}
