<template>
  <div class="min-h-screen bg-[#0f172a] flex items-center justify-center p-4">
    <div class="max-w-md w-full bg-[#1e293b]/80 backdrop-blur-md rounded-xl shadow-2xl border border-slate-700/50 p-8">
      <div class="text-center mb-8">
        <h1 class="text-3xl font-black tracking-tighter text-transparent bg-clip-text bg-gradient-to-r from-blue-400 via-indigo-400 to-emerald-400 filter drop-shadow-lg mb-2">
          INSTITUTIONAL EDGE
        </h1>
        <p class="text-slate-400 text-sm font-mono tracking-wide">PROFESSIONAL TRADING TERMINAL</p>
      </div>

      <form @submit.prevent="handleLogin" class="space-y-6">
        <div>
          <label class="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-2">Username</label>
          <input 
            v-model="username" 
            type="text" 
            required
            class="w-full bg-slate-900/50 border border-slate-700 rounded-lg px-4 py-3 text-white placeholder-slate-600 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none transition-all"
            placeholder="Enter your username"
          >
        </div>

        <div>
          <label class="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-2">Password</label>
          <input 
            v-model="password" 
            type="password" 
            required
            class="w-full bg-slate-900/50 border border-slate-700 rounded-lg px-4 py-3 text-white placeholder-slate-600 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none transition-all"
            placeholder="Enter your password"
          >
        </div>

        <div v-if="error" class="text-red-400 text-xs text-center bg-red-500/10 border border-red-500/20 rounded p-2">
          {{ error }}
        </div>

        <button 
          type="submit" 
          :disabled="loading"
          class="w-full bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-500 hover:to-indigo-500 text-white font-bold py-3 rounded-lg shadow-lg shadow-blue-900/20 transition-all transform active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <span v-if="loading" class="flex items-center justify-center">
            <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            AUTHENTICATING...
          </span>
          <span v-else>ACCESS TERMINAL</span>
        </button>
      </form>

      <div class="mt-6 text-center">
        <router-link to="/register" class="text-xs text-slate-500 hover:text-blue-400 transition-colors">
          Don't have an account? Register Access
        </router-link>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import api from '../services/api';

const router = useRouter();
const username = ref('');
const password = ref('');
const error = ref('');
const loading = ref(false);

const handleLogin = async () => {
  loading.value = true;
  error.value = '';
  
  try {
    await api.login(username.value, password.value);
    router.push('/');
  } catch (e) {
    error.value = e.response?.data?.detail || 'Authentication failed. Please check your credentials.';
  } finally {
    loading.value = false;
  }
};
</script>
