const fs = require('fs')

module.exports = {
  buildPlaceholderSet: function () {
    var placeholderSet = new Set()
    var data
    var dataString
    var regex
    var result

    // util_replace_placeholders_spec
    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/util_replace_placeholders_spec.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open util_replace_placeholders_spec.rb")
      atom.notifications.addError(err.toString())
      return
    }
    dataString = data.toString()
    regex = /it \"\[(.*)\]\" do/g
    result = regex.exec(dataString)
    while (result != null) {
      placeholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/ /g, ''))
      result = regex.exec(dataString)
    }

    // user_loan_app
    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/user_loan_app.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open user_loan_app.rb")
      atom.notifications.addError(err.toString())
      return
    }
    dataString = data.toString()
    regex = /values\[(.*?)\]/g
    result = regex.exec(dataString)
    while (result != null) {
      placeholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/ /g, ''))
      result = regex.exec(dataString)
    }

    // custom_form
    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/custom_form.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open custom_form.rb")
      atom.notifications.addError(err.toString())
      return
    }
    dataString = data.toString()
    regex = /set_value form_def, (.*?),/g
    result = regex.exec(dataString)
    while (result != null) {
      placeholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/ /g, ''))
      result = regex.exec(dataString)
    }

    // time_placeholder_replacement
    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/time_placeholder_replacement.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open time_placeholder_replacement.rb")
      atom.notifications.addError(err.toString())
      return
    }
    dataString = data.toString()
    regex = /\[(.*?)\]/g
    result = regex.exec(dataString)
    while (result != null) {
      placeholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/ /g, ''))
      result = regex.exec(dataString)
    }

    // lending_qb
    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/lending_qb.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open lending_qb.rb")
      atom.notifications.addError(err.toString())
      return
    }
    dataString = data.toString()
    regex = /values\[(.*?)\]/g
    result = regex.exec(dataString)
    while (result != null) {
      placeholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/ /g, ''))
      result = regex.exec(dataString)
    }

    // remove bogus entries (maybe I should do this via modified regexp)
    placeholderSet.forEach(function(item){
      if (item.toString().includes("+")) {
        placeholderSet.delete(item)
      } else if (item.toString().includes("CUSTOM_")) {
        placeholderSet.delete(item)
      } else if (item.toString().includes(".")) {
        placeholderSet.delete(item)
      } else if (item.toString() == "") {
        placeholderSet.delete(item)
      }
    });

    return placeholderSet
  }
}
