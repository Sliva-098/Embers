'use strict';
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('embers', {
  cmd: (name, arg) => ipcRenderer.invoke('cmd', name, arg),
  state: () => ipcRenderer.invoke('state'),
  games: () => ipcRenderer.invoke('games'),
  onState: (cb) => ipcRenderer.on('state', (_e, s) => cb(s)),
  onGames: (cb) => ipcRenderer.on('games-updated', () => cb()),
});
