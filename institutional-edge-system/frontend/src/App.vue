<template>
  <div class="min-h-screen bg-background font-sans text-text-primary flex">
    
    <!-- Sidebar Navigation -->
    <aside v-if="!isStreamMode" class="w-64 bg-surface border-r border-slate-200 flex flex-col fixed h-full z-40 transition-all duration-300" :class="isSidebarOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'">
      <div class="p-6 border-b border-slate-200 flex items-center justify-between">
        <div class="flex items-center space-x-2">
           <div class="w-8 h-8 bg-accent rounded-lg flex items-center justify-center text-white font-black text-lg">IE</div>
           <div class="font-black text-lg tracking-tighter text-primary">INSTITUTIONAL<span class="text-accent">EDGE</span></div>
        </div>
        <button @click="isSidebarOpen = false" class="lg:hidden text-slate-400 hover:text-primary">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
        </button>
      </div>

      <nav class="flex-1 p-4 space-y-2 overflow-y-auto">
        <router-link to="/" class="flex items-center space-x-3 px-4 py-3 rounded-lg font-bold text-sm transition-colors" :class="$route.path === '/' ? 'bg-accent/10 text-accent' : 'text-slate-500 hover:bg-slate-50 hover:text-primary'">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" /></svg>
          <span>Dashboard</span>
        </router-link>
        
        <router-link to="/signals" class="flex items-center space-x-3 px-4 py-3 rounded-lg font-bold text-sm transition-colors" :class="$route.path === '/signals' ? 'bg-accent/10 text-accent' : 'text-slate-500 hover:bg-slate-50 hover:text-primary'">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" /></svg>
          <span>Signals</span>
        </router-link>

        <router-link to="/backtest" class="flex items-center space-x-3 px-4 py-3 rounded-lg font-bold text-sm transition-colors" :class="$route.path === '/backtest' ? 'bg-accent/10 text-accent' : 'text-slate-500 hover:bg-slate-50 hover:text-primary'">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" /></svg>
          <span>Backtest</span>
        </router-link>

        <router-link to="/settings" class="flex items-center space-x-3 px-4 py-3 rounded-lg font-bold text-sm transition-colors" :class="$route.path === '/settings' ? 'bg-accent/10 text-accent' : 'text-slate-500 hover:bg-slate-50 hover:text-primary'">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" /></svg>
          <span>Settings</span>
        </router-link>
      </nav>

      <div class="p-4 border-t border-slate-200">
        <div class="flex items-center space-x-3 px-4 py-3 rounded-lg bg-slate-50 border border-slate-100">
           <div class="w-8 h-8 rounded-full bg-slate-200 flex items-center justify-center text-xs font-bold text-slate-500">U</div>
           <div class="flex-1 min-w-0">
             <div class="text-xs font-bold text-primary truncate">User</div>
             <div class="text-[10px] text-slate-400 truncate">Pro Plan</div>
           </div>
        </div>
      </div>
    </aside>

    <!-- Mobile Menu Button -->
    <button v-if="!isStreamMode && !isSidebarOpen" @click="isSidebarOpen = true" class="lg:hidden fixed top-4 left-4 z-50 p-2 bg-white rounded-lg shadow-md border border-slate-200 text-slate-500">
      <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" /></svg>
    </button>

    <!-- Main Content -->
    <main class="flex-1 transition-all duration-300" :class="!isStreamMode ? 'lg:ml-64' : ''">
      <router-view :privacy-mode="privacyMode"></router-view>
    </main>

  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useRoute } from 'vue-router'

const route = useRoute()
const privacyMode = ref(false)
const isSidebarOpen = ref(false)

const isStreamMode = computed(() => route.path === '/stream')

function togglePrivacy() {
  privacyMode.value = !privacyMode.value
}
</script>
