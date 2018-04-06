'use babel';

const fs = require('fs')

const showModal = require('./showModal')

module.exports = {
  showAvailablePlaceholders: function (placeholderSet) {
    showModal.displayModal(Array.from(placeholderSet).sort().toString().replace(/,/g, '<br>'))
  }
}
