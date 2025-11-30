<template>
  <div class="min-h-screen bg-background flex items-center justify-center p-4">
    <div class="max-w-md w-full bg-white rounded-xl shadow-card border border-slate-200 p-8">
      <div class="text-center mb-8">
        <h1 class="text-3xl font-black tracking-tighter text-primary mb-2">
          INSTITUTIONAL <span class="text-accent">EDGE</span>
        </h1>
        <p class="text-slate-500 text-sm font-mono tracking-wide">REQUEST ACCESS</p>
      </div>

      <form @submit.prevent="handleRegister" class="space-y-6">
        <div>
          <label class="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-2">Email Address</label>
          <input 
            v-model="email" 
            type="email" 
            required
            class="w-full bg-slate-50 border border-slate-200 rounded-lg px-4 py-3 text-primary placeholder-slate-400 focus:border-accent focus:ring-1 focus:ring-accent outline-none transition-all"
            placeholder="Enter your email"
          >
        </div>

        <div>
          <label class="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-2">Username</label>
          <input 
            v-model="username" 
            type="text" 
            required
            class="w-full bg-slate-50 border border-slate-200 rounded-lg px-4 py-3 text-primary placeholder-slate-400 focus:border-accent focus:ring-1 focus:ring-accent outline-none transition-all"
            placeholder="Choose a username"
          >
        </div>

        <div>
          <label class="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-2">Password</label>
          <input 
            v-model="password" 
            type="password" 
            required
            class="w-full bg-slate-50 border border-slate-200 rounded-lg px-4 py-3 text-primary placeholder-slate-400 focus:border-accent focus:ring-1 focus:ring-accent outline-none transition-all"
            placeholder="Choose a strong password"
          >
        </div>

        <div v-if="error" class="text-danger text-xs text-center bg-danger/10 border border-danger/20 rounded p-2">
          {{ error }}
        </div>

        <button 
          type="submit" 
          :disabled="loading"
          class="w-full bg-accent hover:bg-accent-hover text-white font-bold py-3 rounded-lg shadow-sm transition-all transform active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <span v-if="loading" class="flex items-center justify-center">
            <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            CREATING ACCOUNT...
          </span>
          <span v-else>REGISTER ACCOUNT</span>
        </button>
      </form>

      <div class="mt-6 text-center">
        <router-link to="/login" class="text-xs text-slate-500 hover:text-accent transition-colors">
          Already have an account? Login
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
const email = ref('');
const username = ref('');
const password = ref('');
const error = ref('');
const loading = ref(false);

const handleRegister = async () => {
  loading.value = true;
  error.value = '';
  
  try {
    await api.register(email.value, username.value, password.value);
    // Auto login or redirect to login
    await api.login(username.value, password.value);
    router.push('/');
  } catch (e) {
    error.value = e.response?.data?.detail || 'Registration failed. Please try again.';
  } finally {
    loading.value = false;
  }
};
</script>
