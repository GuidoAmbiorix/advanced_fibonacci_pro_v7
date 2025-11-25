import { createRouter, createWebHistory } from 'vue-router'
import ExecutionDashboard from '../components/ExecutionDashboard.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      component: ExecutionDashboard
    },
    {
      path: '/signals',
      name: 'signals',
      component: () => import('../views/SignalsView.vue')
    }
  ]
})

export default router
