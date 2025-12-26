<template>
  <div class="space-y-6">
    <div class="flex justify-between items-center">
      <h3 class="text-lg font-semibold text-slate-700">Trading Accounts</h3>
      <div class="flex gap-2">
         <button 
          @click="showTerminalManager = !showTerminalManager" 
          class="px-3 py-2 bg-gray-600 text-white rounded hover:bg-gray-700 text-sm"
        >
          <i class="fas fa-server mr-1"></i> Terminals
        </button>
        <button 
          @click="openAddModal" 
          class="px-3 py-2 bg-accent text-white rounded hover:bg-accent/90 text-sm"
        >
          <i class="fas fa-plus mr-1"></i> Add Account
        </button>
      </div>
    </div>

    <!-- Terminals Toggle (Collapsible) -->
    <div v-if="showTerminalManager" class="mb-6 animate-fadeIn">
        <TerminalManager />
    </div>

    <!-- Accounts List -->
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      <div 
        v-for="acc in accounts" 
        :key="acc.id" 
        class="border border-slate-200 rounded-lg p-4 bg-white shadow-sm hover:shadow-md transition-shadow relative"
      >
        <div class="absolute top-4 right-4 text-xs font-bold px-2 py-1 rounded" 
             :class="acc.is_active ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'">
            {{ acc.is_active ? 'ACTIVE' : 'IDLE' }}
        </div>

        <div class="mb-2">
            <h4 class="font-bold text-slate-700">{{ acc.name }}</h4>
            <p class="text-xs text-slate-400">{{ acc.server }}</p>
        </div>

        <div class="space-y-1 text-sm text-slate-600 mb-4">
             <div class="flex justify-between border-b border-gray-100 py-1">
                <span>Login:</span> <span class="font-mono">{{ acc.login }}</span>
             </div>
             <div class="flex justify-between border-b border-gray-100 py-1">
                <span>Terminal:</span> 
                <span class="font-mono text-xs truncate max-w-[150px]" :title="acc.terminal_path">
                    {{ formatPath(acc.terminal_path) }}
                </span>
             </div>
        </div>

        <div class="flex gap-2 mt-2">
            <button class="flex-1 text-xs py-1 border border-slate-300 rounded hover:bg-slate-50">Edit</button>
            <button class="flex-1 text-xs py-1 border border-red-200 text-red-600 rounded hover:bg-red-50">Disconnect</button>
        </div>
      </div>
      
      <!-- Empty State -->
      <div v-if="accounts.length === 0" class="col-span-full text-center py-8 text-slate-400 bg-slate-50 rounded border border-dashed border-slate-300">
        No accounts linked. Add an MT5, HFM, or Funded account.
      </div>
    </div>

    <!-- Add Account Modal -->
    <div v-if="showModal" class="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50">
       <div class="bg-white rounded-xl p-6 w-full max-w-lg shadow-2xl">
           <h3 class="text-xl font-bold mb-4">Link New Account</h3>
           
           <div class="space-y-4">
               <div>
                   <label class="block text-xs font-bold text-slate-500 uppercase mb-1">Account Name (Alias)</label>
                   <input v-model="form.name" type="text" placeholder="e.g. HFM Live 1" class="w-full border rounded p-2">
               </div>
               
               <div class="grid grid-cols-2 gap-4">
                   <div>
                       <label class="block text-xs font-bold text-slate-500 uppercase mb-1">MT5 Login</label>
                       <input v-model="form.login" type="text" class="w-full border rounded p-2">
                   </div>
                   <div>
                       <label class="block text-xs font-bold text-slate-500 uppercase mb-1">MT5 Password</label>
                       <input v-model="form.password" type="password" class="w-full border rounded p-2">
                   </div>
               </div>
               
               <div>
                   <label class="block text-xs font-bold text-slate-500 uppercase mb-1">Server</label>
                   <input v-model="form.server" type="text" placeholder="e.g. HFMarkets-Live" class="w-full border rounded p-2">
               </div>

               <div>
                   <label class="block text-xs font-bold text-slate-500 uppercase mb-1">Select Terminal Instance</label>
                   <select v-model="form.terminal_path" class="w-full border rounded p-2">
                       <option value="" disabled>Select a terminal...</option>
                       <option v-for="t in terminalList" :key="t.path" :value="t.path">
                           {{ t.name }} ({{ t.path }})
                       </option>
                   </select>
                   <p class="text-xs text-slate-400 mt-1">
                       <i class="fas fa-info-circle"></i> Selecting a dedicated cloned terminal is recommended for multi-account stability.
                   </p>
               </div>
           </div>

           <div class="flex justify-end gap-3 mt-8">
             <button @click="showModal = false" class="px-4 py-2 hover:bg-slate-100 rounded text-slate-500">Cancel</button>
             <button @click="saveAccount" class="px-4 py-2 bg-accent text-white rounded font-bold hover:bg-accent/90">Save Account</button>
           </div>
       </div>
    </div>

  </div>
</template>

<script setup>
import { ref, onMounted, defineProps } from 'vue';
import TerminalManager from './TerminalManager.vue';
import api from '../../services/api'; 
// import { useToast } from 'vue-toastification';

const props = defineProps(['botId']);
// const toast = useToast();

const accounts = ref([]);
const showTerminalManager = ref(false);
const showModal = ref(false);
const terminalList = ref([]);
const loading = ref(false);

const form = ref({
    name: '',
    login: '',
    password: '',
    server: '',
    terminal_path: ''
});

const loadAccounts = async () => {
    if (!props.botId) return;
    try {
        loading.value = true;
        accounts.value = await api.getBotAccounts(props.botId);
    } catch (e) {
        console.error("Failed to load accounts:", e);
        // toast.error("Failed to load accounts");
    } finally {
        loading.value = false;
    }
};

const loadTerminals = async () => {
    try {
        terminalList.value = await api.getTerminals();
    } catch(e) {
        console.error("Failed to load terminals:", e);
        // toast.error("Failed to load terminal list");
    }
};

const openAddModal = async () => {
    await loadTerminals();
    form.value = {
        name: '',
        login: '',
        password: '',
        server: '',
        terminal_path: ''
    };
    showModal.value = true;
};

const saveAccount = async () => {
    if (!form.value.login || !form.value.terminal_path) {
        alert("Please fill required fields (Login & Terminal)");
        return;
    }
    
    try {
        await api.createBotAccount(props.botId, form.value);
        alert("Account linked successfully");
        showModal.value = false;
        loadAccounts();
    } catch(e) {
        console.error(e);
        alert("Failed to add account: " + (e.response?.data?.detail || e.message));
    }
};

const formatPath = (path) => {
    if(!path) return 'Default';
    const parts = path.split('\\');
    return parts[parts.length - 1];
};

onMounted(() => {
    loadAccounts();
});
</script>
