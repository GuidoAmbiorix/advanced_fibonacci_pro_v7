/**
 * TradingView Integration - Composable for Notifications
 * Handles browser notifications and in-app toasts
 */

import { ref } from 'vue'

export interface ToastNotification {
  id: string
  type: 'success' | 'error' | 'warning' | 'info'
  title: string
  message: string
  duration?: number
}

export function useNotifications() {
  const notifications = ref<ToastNotification[]>([])
  const permissionGranted = ref(false)

  // Request browser notification permission
  const requestPermission = async () => {
    if ('Notification' in window) {
      const permission = await Notification.requestPermission()
      permissionGranted.value = permission === 'granted'
      return permissionGranted.value
    }
    return false
  }

  // Show browser notification
  const showBrowserNotification = (title: string, options?: NotificationOptions) => {
    if (permissionGranted.value && 'Notification' in window) {
      new Notification(title, {
        icon: '/favicon.ico',
        ...options
      })
    }
  }

  // Show toast notification
  const showToast = (
    type: ToastNotification['type'],
    title: string,
    message: string,
    duration: number = 5000
  ) => {
    const id = `toast-${Date.now()}-${Math.random()}`

    const notification: ToastNotification = {
      id,
      type,
      title,
      message,
      duration
    }

    notifications.value.push(notification)

    // Auto-dismiss
    if (duration > 0) {
      setTimeout(() => {
        dismissNotification(id)
      }, duration)
    }

    return id
  }

  // Dismiss notification
  const dismissNotification = (id: string) => {
    const index = notifications.value.findIndex(n => n.id === id)
    if (index !== -1) {
      notifications.value.splice(index, 1)
    }
  }

  // Convenience methods
  const success = (title: string, message: string) => {
    showToast('success', title, message)
  }

  const error = (title: string, message: string) => {
    showToast('error', title, message, 7000) // Errors stay longer
  }

  const warning = (title: string, message: string) => {
    showToast('warning', title, message)
  }

  const info = (title: string, message: string) => {
    showToast('info', title, message)
  }

  // Play notification sound
  const playSound = (type: 'signal' | 'trade' | 'error') => {
    const sounds = {
      signal: '/sounds/signal.mp3',
      trade: '/sounds/trade.mp3',
      error: '/sounds/error.mp3'
    }

    const audio = new Audio(sounds[type])
    audio.volume = 0.5
    audio.play().catch(() => {
      console.warn('Could not play notification sound')
    })
  }

  return {
    notifications,
    permissionGranted,
    requestPermission,
    showBrowserNotification,
    showToast,
    dismissNotification,
    success,
    error,
    warning,
    info,
    playSound
  }
}
