'use babel';

const fs = require('fs')

const showModal = require('./showModal')

module.exports = {
  showAvailablePlaceholders: function () {
    try {
      var data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/util_replace_placeholders_spec.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open util_replace_placeholders_spec.rb")
      atom.notifications.addError(err.toString())
      return
    }
    var dataString = data.toString()
    var regex = /it \"(.*)\" do/g
    var set = new Set()
    var result = regex.exec(dataString)
    while (result != null) {
      set.add(result[1])
      result = regex.exec(dataString)
    }
    showModal.displayModal(Array.from(set).sort().toString().replace(/,/g, '<br>'))
    // showModal.displayModal(Array.toString())
    // showModal.displayModal(JSON.stringify(Array.from(set).sort()), null, 2)
  }
}
