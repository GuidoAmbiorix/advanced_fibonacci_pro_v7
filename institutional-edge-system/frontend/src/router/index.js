import { createRouter, createWebHistory } from 'vue-router'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      redirect: '/backtest'
    },
    {
      path: '/signals',
      name: 'signals',
      component: () => import('../views/SignalsView.vue'),
    },
    {
      path: '/settings',
      name: 'settings',
      component: () => import('../views/SettingsView.vue'),
    },
    {
      path: '/performance',
      name: 'performance',
      component: () => import('../views/PerformanceView.vue'),
    },
    {
      path: '/backtest',
      name: 'backtest',
      component: () => import('../views/BacktestView.vue'),
    },
    {
      path: '/accounts',
      name: 'accounts',
      component: () => import('../views/AccountsView.vue'),
    },
    {
      path: '/logs',
      name: 'logs',
      component: () => import('../views/SystemLogs.vue'),
    },
    {
      path: '/quant-analysis',
      name: 'quant-analysis',
      component: () => import('../views/QuantAnalysisView.vue'),
    }
  ]
})

export default router
