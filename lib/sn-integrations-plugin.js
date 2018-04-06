'use babel';

import { CompositeDisposable } from 'atom';

import { TouchBar, nativeImage } from 'remote';

const insertBoilerPlateFile = require('./insertBoilerPlateFile')
const beautifySimplenexusJson = require('./beautifySimpleNexusJson')
const showAvailablePlaceholders = require('./showAvailablePlaceholders')
const showModal = require('./showModal')
const snProvider = require('./snProvider')
const buildPlaceholderSet = require('./buildPlaceholderSet')

import { dispatchAction } from './dispatchAction';

let currentTouchBar;

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
    // touchbar stuff

    if (TouchBar) {
      const {
        TouchBarButton,
        TouchBarColorPicker,
        TouchBarGroup,
        TouchBarLabel,
        TouchBarPopover,
        TouchBarScrubber,
        TouchBarSegmentedControl,
        TouchBarSlider,
        TouchBarSpacer
      } = TouchBar
      var elements = []
      var button = new TouchBarButton({label: 'Beautify JSON', icon: nativeImage.createFromPath(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/simplenexus-icon-transparent.png'), iconPosition: 'left', click: function() { atom.commands.dispatch(atom.views.getView(atom.workspace.getActiveTextEditor()), 'sn-integrations-plugin:beautify')}})
      elements.push(button)
      currentTouchBar = new TouchBar({items: elements})
      atom.getCurrentWindow().setTouchBar(currentTouchBar)
    }

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
