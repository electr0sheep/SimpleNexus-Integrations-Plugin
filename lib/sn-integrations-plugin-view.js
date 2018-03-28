'use babel';

export default class SnIntegrationsPluginView {

  // message: null,

  // var message = document.createElement('div');

  // setMessage(newMessage) {
  //   this.message.textContent = newMessage;
  // },

  // var message;

  constructor(serializedState) {
    // Create root element
    this.element = document.createElement('div');
    this.element.classList.add('sn-integrations-plugin');
``
    // Create message element
    this.message = document.createElement('div');
    message.textContent = 'The SnIntegrationsPlugin package is Alive! It\'s ALIVE!';

    message.classList.add('message');

    const button = document.createElement('btn');
    button.textContent = 'Okay';
    button.classList.add('btn');
    button.classList.add('btn-lg')
    button.classList.add('btn-primary');
    // console.log(this)
    button.onclick = function () {
      var thisModal;
      for (var i = 0; i < atom.workspace.getModalPanels().length; i++) {
        if (atom.workspace.getModalPanels()[i].item.outerHTML.startsWith("<div class=\"sn-integrations-plugin\"")) {
          thisModal = atom.workspace.getModalPanels()[i];
          break;
        }
      }
      thisModal.hide();
    }
    this.element.appendChild(message);
    this.element.appendChild(button);
    // console.log(Object.keys(button));
  }

  // Returns an object that can be retrieved when package is activated
  serialize() {}

  // Tear down any state and detach
  destroy() {
    this.element.remove();
  }

  getElement() {
    return this.element;
  }

}
