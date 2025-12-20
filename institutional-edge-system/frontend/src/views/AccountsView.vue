<template>
  <div class="min-h-screen bg-gray-900 text-white p-6">
    <!-- Header -->
    <div class="max-w-4xl mx-auto">
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">MT5 Accounts</h1>
          <p class="text-gray-400 mt-1">Manage your trading accounts and prop firm rules</p>
        </div>
        <button 
          @click="showAddModal = true"
          class="px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg flex items-center gap-2 transition-colors"
        >
          <span>+</span>
          Add Account
        </button>
      </div>

      <!-- Active Account Banner -->
      <div v-if="activeAccount" class="mb-6 p-4 bg-green-900/30 border border-green-600 rounded-xl">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <span class="text-2xl">🔗</span>
            <div>
              <div class="font-bold text-green-400">Connected: {{ activeAccount.name }}</div>
              <div class="text-sm text-gray-400">{{ activeAccount.login }} @ {{ activeAccount.server }}</div>
            </div>
          </div>
          <button 
            @click="disconnectAccount(activeAccount.id)"
            class="px-3 py-1 bg-red-600 hover:bg-red-500 text-white text-sm rounded transition-colors"
          >
            Disconnect
          </button>
        </div>
      </div>

      <!-- Accounts List -->
      <div class="space-y-4">
        <div v-if="accounts.length === 0" class="text-center py-12 text-gray-500">
          <div class="text-4xl mb-4">💳</div>
          <p>No accounts yet. Add your first MT5 account.</p>
        </div>

        <div 
          v-for="account in accounts" 
          :key="account.id"
          class="bg-gray-800 rounded-xl p-4 border transition-colors"
          :class="account.is_active ? 'border-green-600' : 'border-gray-700 hover:border-gray-600'"
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <!-- Account Type Badge -->
              <div 
                class="px-2 py-1 rounded text-xs font-bold uppercase"
                :class="{
                  'bg-blue-900 text-blue-400': account.account_type === 'demo',
                  'bg-green-900 text-green-400': account.account_type === 'live',
                  'bg-purple-900 text-purple-400': account.account_type === 'prop'
                }"
              >
                {{ account.account_type }}
              </div>
              
              <!-- Account Info -->
              <div>
                <div class="font-bold text-lg">{{ account.name }}</div>
                <div class="text-sm text-gray-400">{{ account.login }} @ {{ account.server }}</div>
              </div>
            </div>

            <!-- Prop Firm Rules -->
            <div class="flex items-center gap-6">
              <div class="text-center">
                <div class="text-xs text-gray-500">Max DD</div>
                <div class="text-sm font-bold text-red-400">{{ account.max_drawdown_percent }}%</div>
              </div>
              <div class="text-center">
                <div class="text-xs text-gray-500">Daily DD</div>
                <div class="text-sm font-bold text-orange-400">{{ account.max_daily_dd_percent }}%</div>
              </div>
              <div class="text-center" v-if="account.symbol_prefix || account.symbol_suffix">
                <div class="text-xs text-gray-500">Prefix/Suffix</div>
                <div class="text-sm font-bold text-yellow-400">{{ account.symbol_prefix || '-' }} / {{ account.symbol_suffix || '-' }}</div>
              </div>

              <!-- Actions -->
              <div class="flex gap-2">
                <button 
                  v-if="!account.is_active"
                  @click="connectAccount(account.id)"
                  class="px-3 py-1.5 bg-green-600 hover:bg-green-500 text-white text-sm rounded transition-colors"
                >
                  Connect
                </button>
                <button 
                  @click="deleteAccount(account.id)"
                  class="px-3 py-1.5 bg-red-900 hover:bg-red-800 text-red-400 text-sm rounded transition-colors"
                  :disabled="account.is_active"
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Add Account Modal -->
    <div v-if="showAddModal" class="fixed inset-0 bg-black/70 flex items-center justify-center z-50">
      <div class="bg-gray-800 rounded-xl p-6 w-full max-w-lg border border-gray-700">
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-xl font-bold">Add MT5 Account</h2>
          <button @click="showAddModal = false" class="text-gray-400 hover:text-white text-xl">✕</button>
        </div>

        <form @submit.prevent="createAccount" class="space-y-4">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm text-gray-400 mb-1">Account Name</label>
              <input 
                v-model="newAccount.name" 
                type="text" 
                placeholder="FundedPips Demo"
                class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg focus:border-blue-500 focus:outline-none"
                required
              />
            </div>
            <div>
              <label class="block text-sm text-gray-400 mb-1">Account Type</label>
              <select 
                v-model="newAccount.account_type"
                class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg focus:border-blue-500 focus:outline-none"
              >
                <option value="demo">Demo</option>
                <option value="live">Live</option>
                <option value="prop">Prop Firm</option>
              </select>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm text-gray-400 mb-1">MT5 Login</label>
              <input 
                v-model="newAccount.login" 
                type="text" 
                placeholder="49290627"
                class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg focus:border-blue-500 focus:outline-none"
                required
              />
            </div>
            <div>
              <label class="block text-sm text-gray-400 mb-1">Password</label>
              <input 
                v-model="newAccount.password" 
                type="password" 
                placeholder="••••••••"
                class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg focus:border-blue-500 focus:outline-none"
                required
              />
            </div>
          </div>

          <div>
            <label class="block text-sm text-gray-400 mb-1">Server</label>
            <input 
              v-model="newAccount.server" 
              type="text" 
              placeholder="HFMarketsGlobal-Demo"
              class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg focus:border-blue-500 focus:outline-none"
              required
            />
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm text-gray-400 mb-1">Symbol Prefix</label>
              <input 
                v-model="newAccount.symbol_prefix" 
                type="text" 
                placeholder="# (for HFM crypto)"
                class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg focus:border-blue-500 focus:outline-none"
              />
            </div>
            <div>
              <label class="block text-sm text-gray-400 mb-1">Symbol Suffix</label>
              <input 
                v-model="newAccount.symbol_suffix" 
                type="text" 
                placeholder="m (for some brokers)"
                class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg focus:border-blue-500 focus:outline-none"
              />
            </div>
          </div>

          <!-- Prop Firm Rules -->
          <div class="border-t border-gray-700 pt-4 mt-4">
            <h3 class="text-sm font-bold text-gray-300 mb-3">Prop Firm Rules (FundedPips)</h3>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm text-gray-400 mb-1">Max Drawdown %</label>
                <input 
                  v-model.number="newAccount.max_drawdown_percent" 
                  type="number" 
                  step="0.1"
                  class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg focus:border-blue-500 focus:outline-none"
                />
              </div>
              <div>
                <label class="block text-sm text-gray-400 mb-1">Max Daily DD %</label>
                <input 
                  v-model.number="newAccount.max_daily_dd_percent" 
                  type="number" 
                  step="0.1"
                  class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg focus:border-blue-500 focus:outline-none"
                />
              </div>
            </div>
          </div>

          <div class="flex gap-3 pt-4">
            <button 
              type="button"
              @click="showAddModal = false"
              class="flex-1 py-2 bg-gray-700 hover:bg-gray-600 text-white rounded-lg transition-colors"
            >
              Cancel
            </button>
            <button 
              type="submit"
              class="flex-1 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg transition-colors"
              :disabled="isLoading"
            >
              {{ isLoading ? 'Adding...' : 'Add Account' }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import axios from 'axios'

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000'

// State
const accounts = ref([])
const showAddModal = ref(false)
const isLoading = ref(false)

const newAccount = ref({
  name: '',
  login: '',
  password: '',
  server: '',
  symbol_prefix: '',
  symbol_suffix: '',
  account_type: 'demo',
  max_drawdown_percent: 8.0,
  max_daily_dd_percent: 3.0
})

// Computed
const activeAccount = computed(() => accounts.value.find(a => a.is_active))

// Methods
const fetchAccounts = async () => {
  try {
    const response = await axios.get(`${API_URL}/api/accounts/`)
    accounts.value = response.data
  } catch (error) {
    console.error('Failed to fetch accounts:', error)
  }
}

const createAccount = async () => {
  isLoading.value = true
  try {
    await axios.post(`${API_URL}/api/accounts/`, newAccount.value)
    showAddModal.value = false
    resetForm()
    await fetchAccounts()
  } catch (error) {
    console.error('Failed to create account:', error)
    alert('Failed to create account: ' + (error.response?.data?.detail || error.message))
  } finally {
    isLoading.value = false
  }
}

const connectAccount = async (accountId) => {
  try {
    await axios.post(`${API_URL}/api/accounts/${accountId}/connect`)
    await fetchAccounts()
  } catch (error) {
    console.error('Failed to connect account:', error)
    alert('Failed to connect: ' + (error.response?.data?.detail || error.message))
  }
}

const disconnectAccount = async (accountId) => {
  try {
    await axios.post(`${API_URL}/api/accounts/${accountId}/disconnect`)
    await fetchAccounts()
  } catch (error) {
    console.error('Failed to disconnect account:', error)
  }
}

const deleteAccount = async (accountId) => {
  if (!confirm('Are you sure you want to delete this account?')) return
  
  try {
    await axios.delete(`${API_URL}/api/accounts/${accountId}`)
    await fetchAccounts()
  } catch (error) {
    console.error('Failed to delete account:', error)
    alert('Failed to delete: ' + (error.response?.data?.detail || error.message))
  }
}

const resetForm = () => {
  newAccount.value = {
    name: '',
    login: '',
    password: '',
    server: '',
    symbol_prefix: '',
    symbol_suffix: '',
    account_type: 'demo',
    max_drawdown_percent: 8.0,
    max_daily_dd_percent: 3.0
  }
}

// Lifecycle
onMounted(() => {
  fetchAccounts()
})
</script>
