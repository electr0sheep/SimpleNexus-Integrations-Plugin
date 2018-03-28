'use babel';

import SnIntegrationsPluginView from './sn-integrations-plugin-view';
import { CompositeDisposable } from 'atom';

const insertBoilerPlateFile = require('./insertBoilerPlateFile')
const beautifySimplenexusJson = require('./beautifySimpleNexusJson')
const showAvailablePlaceholders = require('./showAvailablePlaceholders')

export default {

  snIntegrationsPluginView: null,
  modalPanel: null,
  subscriptions: null,

  config: {
    "showConfirmationDialog": {
      "description": "If you attempt to over-write the contents of a file, shows a confirmation dialog before proceeding (default: true).",
      "type": "boolean",
      "default": true
    }
  },

  activate(state) {
    this.snIntegrationsPluginView = new SnIntegrationsPluginView(state.snIntegrationsPluginViewState);
    this.modalPanel = atom.workspace.addModalPanel({
      item: this.snIntegrationsPluginView.getElement(),
      visible: false
    });

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
      'sn-integrations-plugin:showAvailablePlaceholders': () => showAvailablePlaceholders.showAvailablePlaceholders()
    }));

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:toggle': () => this.toggle()
    }));
  },

  toggle() {
    return (
      this.modalPanel.isVisible() ?
      this.modalPanel.hide() :
      this.modalPanel.show()
    );
  },

  deactivate() {
    this.modalPanel.destroy();
    this.subscriptions.dispose();
    this.snIntegrationsPluginView.destroy();
  }
};
