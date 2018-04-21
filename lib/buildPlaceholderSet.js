const fs = require('fs')

module.exports = {
  buildPlaceholderSet: function () {
    var returnJSON = {}
    var encompassPlaceholderSet = new Set()
    var lqbPlaceholderSet = new Set()
    var nmmPlaceholderSet = new Set()
    var masterPlaceholderSet = new Set()
    var data
    var dataString
    var regex
    var result

    // util_replace_placeholders_spec
    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/simplenexus.com/util_replace_placeholders_spec.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open util_replace_placeholders_spec.rb", {dismissable: true})
      atom.notifications.addError(err.toString(), {dismissable: true})
      return
    }
    dataString = data.toString()
    regex = /it \"\[(.*)\]\" do/g
    result = regex.exec(dataString)
    while (result != null) {
      masterPlaceholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/ /g, ''))
      result = regex.exec(dataString)
    }

    // user_loan_app
    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/simplenexus.com/user_loan_app.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open user_loan_app.rb", {dismissable: true})
      atom.notifications.addError(err.toString(), {dismissable: true})
      return
    }
    dataString = data.toString()
    regex = /values\[(.*?)\]/g
    result = regex.exec(dataString)
    while (result != null) {
      masterPlaceholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/ /g, ''))
      encompassPlaceholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/ /g, ''))
      result = regex.exec(dataString)
    }

    // custom_form
    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/simplenexus.com/custom_form.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open custom_form.rb", {dismissable: true})
      atom.notifications.addError(err.toString(), {dismissable: true})
      return
    }
    dataString = data.toString()
    regex = /set_value form_def, (.*?),/g
    result = regex.exec(dataString)
    while (result != null) {
      masterPlaceholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/ /g, ''))
      result = regex.exec(dataString)
    }

    // time_placeholder_replacement
    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/simplenexus.com/time_placeholder_replacement.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open time_placeholder_replacement.rb", {dismissable: true})
      atom.notifications.addError(err.toString(), {dismissable: true})
      return
    }
    dataString = data.toString()
    regex = /\[(.*?)\]/g
    result = regex.exec(dataString)
    while (result != null) {
      masterPlaceholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/ /g, ''))
      result = regex.exec(dataString)
    }

    // lending_qb
    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/simplenexus.com/lending_qb.rb')
    }
    catch (err) {
      atom.notifications.addError("Unable to open lending_qb.rb", {dismissable: true})
      atom.notifications.addError(err.toString(), {dismissable: true})
      return
    }
    dataString = data.toString()
    regex = /values\[(.*?)\]/g
    result = regex.exec(dataString)
    while (result != null) {
      masterPlaceholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/ /g, ''))
      lqbPlaceholderSet.add(result[1].toString().toUpperCase().replace(/\'/g, '').replace(/\"/g, '').replace(/ /g, ''))
      result = regex.exec(dataString)
    }

    // nmm
    try {
      data = fs.readFileSync(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/default_json_fields.json')
    }
    catch (err) {
      atom.notifications.addError("Unable to open default_json_fields.json", {dismissable: true})
      atom.notifications.addError(err.toString(), {dismissable: true})
      return
    }
    var dataJSON = JSON.parse(data)
    var jsonArray = dataJSON.structure[0].fields
    for (var i = 0; i < jsonArray.length; i++) {
      masterPlaceholderSet.add(jsonArray[i].toUpperCase())
      nmmPlaceholderSet.add(jsonArray[i].toUpperCase())
    }

    // remove bogus entries (maybe I should do this via modified regexp)
    masterPlaceholderSet.forEach(function(item){
      if (item.toString().includes("+")) {
        masterPlaceholderSet.delete(item)
      } else if (item.toString().includes("CUSTOM_")) {
        masterPlaceholderSet.delete(item)
      } else if (item.toString().includes(".")) {
        masterPlaceholderSet.delete(item)
      } else if (item.toString() == "") {
        masterPlaceholderSet.delete(item)
      }
    });

    encompassPlaceholderSet.forEach(function(item){
      if (item.toString().includes("+")) {
        encompassPlaceholderSet.delete(item)
      } else if (item.toString().includes("CUSTOM_")) {
        encompassPlaceholderSet.delete(item)
      } else if (item.toString().includes(".")) {
        encompassPlaceholderSet.delete(item)
      } else if (item.toString() == "") {
        encompassPlaceholderSet.delete(item)
      }
    });

    lqbPlaceholderSet.forEach(function(item){
      if (item.toString().includes("+")) {
        lqbPlaceholderSet.delete(item)
      } else if (item.toString().includes("CUSTOM_")) {
        lqbPlaceholderSet.delete(item)
      } else if (item.toString().includes(".")) {
        lqbPlaceholderSet.delete(item)
      } else if (item.toString() == "") {
        lqbPlaceholderSet.delete(item)
      }
    });

    // now we have 3 sets
    // enocmpassPlaceholderSet has values that should be mapped in encompass
    // lqbPlaceholderSet has values that should be mapped in lqb
    // masterPlaceholderSet has all values, including encompass and lqb

    // lets build a JSON object that has all this information
    masterPlaceholderSet.forEach(function(item) {
      returnJSON[item] = {"encompass": false, "lqb": false, "nmm": false}
    })
    encompassPlaceholderSet.forEach(function(item) {
      returnJSON[item].encompass = true
    })
    lqbPlaceholderSet.forEach(function(item) {
      returnJSON[item].lqb = true
    })
    nmmPlaceholderSet.forEach(function(item) {
      returnJSON[item].nmm = true
    })

    return returnJSON
  }
}
