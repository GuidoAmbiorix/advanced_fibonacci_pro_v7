import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import './assets/main.css'

async function bootstrap() {
  // Auto-login: fetch a system token if we don't have one yet.
  // This is a local trading terminal - no user authentication needed.
  if (!localStorage.getItem('token')) {
    try {
      const res = await fetch('/api/auth/auto-token')
      if (res.ok) {
        const data = await res.json()
        localStorage.setItem('token', data.access_token)
        localStorage.setItem('user', JSON.stringify({
          id: data.user_id,
          username: data.username
        }))
      }
    } catch (e) {
      console.warn('Auto-token fetch failed, will retry on first API call:', e)
    }
  }

  const app = createApp(App)
  app.use(createPinia())
  app.use(router)
  app.mount('#app')
}

bootstrap()
