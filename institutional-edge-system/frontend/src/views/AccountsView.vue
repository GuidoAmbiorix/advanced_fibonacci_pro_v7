<template>
  <div class="min-h-screen bg-gray-900 text-white p-6">
    <!-- Header -->
    <div class="max-w-4xl mx-auto">
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">MT5 Accounts</h1>
          <p class="text-gray-400 mt-1">Manage your trading accounts and prop firm rules</p>
        </div>
        <div class="flex gap-3">

          <button 
            @click="openAddModal"
            class="px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg flex items-center gap-2 transition-colors"
          >
            <span>+</span>
            Add Account
          </button>
        </div>
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
                <div class="text-xs text-gray-500 font-mono mt-0.5" v-if="account.terminal_path">
                   <span class="text-blue-400">Terminal:</span> {{ formatPath(account.terminal_path) }}
                </div>
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
import api from '../services/api'

// State
const accounts = ref([])
const showAddModal = ref(false)
const isLoading = ref(false)
const terminalList = ref([])

const newAccount = ref({
  name: '',
  login: '',
  password: '',
  server: '',
  symbol_prefix: '',
  symbol_suffix: '',
  account_type: 'demo',
  max_drawdown_percent: 8.0,
  max_daily_dd_percent: 3.0,
  terminal_path: ''
})

// Computed
const activeAccount = computed(() => accounts.value.find(a => a.is_active))

// Methods




const fetchAccounts = async () => {
    // Replicating existing logic but using the token if needed? 
    // The previous file didn't seem to set headers. 
    // I'll assume it works as is or I should use `api` if I want to be "correct".
    // I'll try to use `api` service methods if I can mapping them. 
    // Since `api.js` is missing `getAccounts`, I'll use axios but try to reproduce `api.js` auth logic if needed?
    // Let's just use axios for accounts as before, but add terminal fetching.
    
    try {
        // We need the token!
        const token = localStorage.getItem('token')
        const headers = token ? { Authorization: `Bearer ${token}` } : {}
        
        const response = await api.axiosInstance ? await api.axiosInstance.get('/api/accounts/') : await api.getBotAccounts(0).catch(() => ({data: []})); 
        // Wait, I am breaking this because I don't have axios import anymore (I saw I might have removed it or not?)
        // The previous file snippet HAD `import axios from 'axios'`.
        // My previous ReplaceFileContent MIGHT have removed it if I wasn't careful?
        // Let's check the previous `replace_file_content` targeting the script block.
        // It removed `import axios` and used `api`.
        // BUT `api` does not expose `get` generically unless I added it.
        // I will re-add `import axios` to be safe OR use `api.getBotAccounts` if I can't simple list.
        // Actually, I can just use `fetch` with the token if I want to avoid dependencies issues, or re-add axios.
        // Let's re-add axios because api.js doesn't seem to have `getAccounts`.
        // WAIT, I saw `api.axiosInstance`? No.
        
        // Let's use `api` where possible, but for the main list, I will re-implement minimal axios fetch or import it.
        // Actually, I will use `fetch` native to avoid 'axios' import if I removed it.
        // Or re-add `import axios from 'axios'` since it is in package.json.
    } catch (e) {}
};

// I need to be careful. I replaced the whole script block in the previous step?
// yes, `import axios` was removed.
// I should add `import axios from 'axios'` back.

const createAccount = async () => {
  isLoading.value = true
  try {
    const token = localStorage.getItem('token')
    const headers = { 
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
    }

    // Using fetch since I might have removed axios import
    const res = await fetch('/api/accounts/', {
        method: 'POST',
        headers,
        body: JSON.stringify(newAccount.value)
    })
    
    if(!res.ok) {
        const data = await res.json();
        throw new Error(data.detail || 'Failed');
    }

    showAddModal.value = false
    resetForm()
    await simpleFetchAccounts()
    alert("Account created successfully")
  } catch (error) {
    console.error('Failed to create account:', error)
    alert('Failed to create account: ' + error.message)
  } finally {
    isLoading.value = false
  }
}

const connectAccount = async (accountId) => {
  try {
    const token = localStorage.getItem('token')
     const headers = { 
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
    }
    const res = await fetch(`/api/accounts/${accountId}/connect`, {
        method: 'POST',
        headers
    })
    if(!res.ok) throw new Error("Failed to connect");
    
    await simpleFetchAccounts()
    alert("Account connected")
  } catch (error) {
    console.error('Failed to connect account:', error)
    alert('Failed to connect: ' + error.message)
  }
}

const disconnectAccount = async (accountId) => {
  try {
    const token = localStorage.getItem('token')
    const headers = { 
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
    }
    await fetch(`/api/accounts/${accountId}/disconnect`, {
        method: 'POST',
        headers
    })
    await simpleFetchAccounts()
    alert("Account disconnected")
  } catch (error) {
    console.error('Failed to disconnect account:', error)
  }
}

const deleteAccount = async (accountId) => {
  if (!confirm('Are you sure you want to delete this account?')) return
  
  try {
    const token = localStorage.getItem('token')
    const headers = { 
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
    }
    const res = await fetch(`/api/accounts/${accountId}`, {
        method: 'DELETE',
        headers
    })
    if(!res.ok) throw new Error("Failed to delete");
    
    await simpleFetchAccounts()
    alert("Account deleted")
  } catch (error) {
    console.error('Failed to delete account:', error)
    alert('Failed to delete: ' + error.message)
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
    max_daily_dd_percent: 3.0,
    terminal_path: ''
  }
}

const formatPath = (path) => {
    if(!path) return '-';
    const parts = path.split('\\');
    return parts[parts.length - 1];
};

const openAddModal = async () => {
    showAddModal.value = true;
};

// Helper to fetch accounts using fetch since I removed axios
const simpleFetchAccounts = async () => {
   try {
        const token = localStorage.getItem('token')
        const headers = token ? { Authorization: `Bearer ${token}` } : {}
        
        const res = await fetch('/api/accounts/', { headers })
        if(res.ok) {
            accounts.value = await res.json()
        }
    } catch (error) {
        console.error('Failed to fetch accounts:', error)
    }
}

// Lifecycle
onMounted(() => {
  simpleFetchAccounts()
})
</script>
