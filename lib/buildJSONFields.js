const fs = require('fs')

module.exports = {
  build: function () {
    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/default_json_fields.json')
    }
    catch (err) {
      atom.notifications.addError("Unable to open default_json_fields.json")
      atom.notifications.addError(err.toString())
      return
    }
    return JSON.parse(data)
  }
}
