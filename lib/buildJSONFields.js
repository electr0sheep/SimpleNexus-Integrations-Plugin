const fs = require('fs')

module.exports = {
  build: function () {
    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/default_json_fields.json')
    }
    catch (err) {
      atom.notifications.addError("Unable to open default_json_fields.json", {dismissable: true})
      atom.notifications.addError(err.toString(), {dismissable: true})
      return
    }

    return JSON.parse(data)
  }
}
