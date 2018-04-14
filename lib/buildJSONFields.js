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

    // order default_json_fields...in future this needs to be moved to it's own thing
    // var stuff = JSON.parse(data)
    // for (var i = 0; i < stuff.structure[0].fields.length; i++) {
    //   var lowest = stuff.structure[0].fields[i]
    //   for (var i2 = i + 1; i2 < stuff.structure[0].fields.length; i2++) {
    //     if (stuff.structure[0].fields[i2] < stuff.structure[0].fields[i]) {
    //       var temp = stuff.structure[0].fields[i]
    //       stuff.structure[0].fields[i] = stuff.structure[0].fields[i2]
    //       stuff.structure[0].fields[i2] = temp
    //     }
    //   }
    // }
    // fs.writeFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/default_json_fields.json', JSON.stringify(stuff, null, 2))

    return JSON.parse(data)
  }
}
