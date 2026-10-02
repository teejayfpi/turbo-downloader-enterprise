import { useEffect, useRef } from 'react';
import { io } from 'socket.io-client';
import { useDownloadStore } from '../stores/downloadStore';

export function useSocket() {
  const socketRef = useRef(null);
  const updateFromServer = useDownloadStore((s) => s.updateFromServer);
  const addNotification = useDownloadStore((s) => s.addNotification);
  const setConnected = useDownloadStore((s) => s.setConnected);

  useEffect(() => {
    const socket = io({
      transports: ['websocket', 'polling'],
      reconnection: true,
      reconnectionAttempts: Infinity,
      reconnectionDelay: 1000,
      reconnectionDelayMax: 8000,
    });
    socketRef.current = socket;

    socket.on('connect', () => setConnected(true));
    socket.on('disconnect', () => setConnected(false));
    socket.on('downloads:update', updateFromServer);

    socket.on('notification', (notification) => {
      addNotification(notification);
      if (
        notification.type !== 'warning' &&
        'Notification' in window &&
        Notification.permission === 'granted'
      ) {
        try {
          new Notification(notification.title, {
            body: notification.message,
            icon: '/favicon.svg',
            tag: `${notification.title}-${notification.message}`,
          });
        } catch {
          /* notifications unavailable */
        }
      }
    });

    return () => socket.disconnect();
  }, [updateFromServer, addNotification, setConnected]);

  return socketRef.current;
}
