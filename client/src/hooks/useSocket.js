import { useEffect, useRef } from 'react';
import { io } from 'socket.io-client';
import { useDownloadStore } from '../stores/downloadStore';

export function useSocket() {
  const socketRef = useRef(null);
  const updateFromServer = useDownloadStore((state) => state.updateFromServer);
  const addNotification = useDownloadStore((state) => state.addNotification);

  useEffect(() => {
    socketRef.current = io({
      transports: ['websocket', 'polling'],
      reconnection: true,
      reconnectionAttempts: 10,
      reconnectionDelay: 1000
    });

    socketRef.current.on('connect', () => {
      console.log('Socket connected');
    });

    socketRef.current.on('disconnect', () => {
      console.log('Socket disconnected');
    });

    socketRef.current.on('downloads:update', (data) => {
      updateFromServer(data);
    });

    socketRef.current.on('notification', (notification) => {
      addNotification(notification);
      
      // Browser notification if permitted
      if (Notification.permission === 'granted') {
        new Notification(notification.title, {
          body: notification.message,
          icon: '/favicon.svg'
        });
      }
    });

    socketRef.current.on('error', (error) => {
      console.error('Socket error:', error);
    });

    return () => {
      if (socketRef.current) {
        socketRef.current.disconnect();
      }
    };
  }, [updateFromServer, addNotification]);

  return socketRef.current;
}
