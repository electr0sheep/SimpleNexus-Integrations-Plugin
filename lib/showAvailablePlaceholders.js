const fs = require('fs')

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
    atom.confirm({
      type: 'info',
      message: 'List of supported placeholders',
      detail: JSON.stringify(Array.from(set).sort()),
      buttons: ['Okay'],
    })
    // console.log(Array.from(set).sort())
    atom.notifications.addSuccess("You clicked show placeholders")
  }
}
