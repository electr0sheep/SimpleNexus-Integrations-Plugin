'use babel';

import { CompositeDisposable } from 'atom';

const insertBoilerPlateFile = require('./insertBoilerPlateFile')
const beautifySimplenexusJson = require('./beautifySimpleNexusJson')
const showAvailablePlaceholders = require('./showAvailablePlaceholders')
const showModal = require('./showModal')
const snProvider = require('./snProvider')
const buildPlaceholderSet = require('./buildPlaceholderSet')

export default {

  placeholders: null,

  provider: null,

  subscriptions: null,

  config: {
    "showConfirmationDialog": {
      "description": "If you attempt to over-write the contents of a file, shows a confirmation dialog before proceeding (default: true).",
      "type": "boolean",
      "default": true
    }
  },

  provide() {
    if (this.provider == null) {
      this.provider = new snProvider(this.placeholders)
    }

    return this.provider
  },

  activate(state) {
    // build placeholder set
    this.placeholders = buildPlaceholderSet.buildPlaceholderSet()

    // Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    this.subscriptions = new CompositeDisposable();

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:beautify': () => beautifySimplenexusJson.beautifySimpleNexusJson()
    }));

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:generate1003Json': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/defaultforms/1003/defaultform.json', "1003 JSON")
    }));

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:generatePrequalHtml': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/defaultforms/prequal/defaultform.html', "PreQual HTML")
    }));

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:generatePrequalJson': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/defaultforms/prequal/defaultform.json', "PreQual JSON")
    }));

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:generatePreapprovalHtml': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/defaultforms/preapproval/defaultform.html', "PreApproval HTML")
    }));

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:generatePreapprovalJson': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/defaultforms/preapproval/defaultform.json', "PreApproval JSON")
    }));

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:showAvailablePlaceholders': () => showAvailablePlaceholders.showAvailablePlaceholders(this.placeholders)
    }));
  },

  deactivate() {
    this.subscriptions.dispose();
  }
};
