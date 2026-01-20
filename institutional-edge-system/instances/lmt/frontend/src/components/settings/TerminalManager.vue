<template>
  <div class="card p-6 space-y-6">
    <div class="flex justify-between items-center">
      <div>
        <h3 class="text-lg font-bold text-primary">Terminal Manager</h3>
        <p class="text-sm text-gray-400">Manage MT5 Terminal Instances for Multi-Account Trading</p>
      </div>
      <button 
        @click="detectTerminals" 
        class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded text-sm transition-colors flex items-center gap-2"
        :disabled="loading"
      >
        <i class="fas fa-sync-alt" :class="{ 'fa-spin': loading }"></i>
        Scan Terminals
      </button>
    </div>

    <!-- Terminal List -->
    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div 
        v-for="term in terminals" 
        :key="term.path" 
        class="p-4 rounded-lg border border-gray-700 bg-gray-800/50 hover:border-accent transition-colors relative group"
      >
        <div class="flex items-start justify-between">
          <div>
            <div class="font-semibold text-white flex items-center gap-2">
              <i class="fas fa-terminal text-accent"></i>
              {{ term.name }}
            </div>
            <div class="text-xs text-gray-400 mt-1 font-mono break-all">{{ term.path }}</div>
             <div class="text-xs text-green-400 mt-2 flex items-center gap-1">
               <i class="fas fa-check-circle"></i> Valid Installation
             </div>
          </div>
          
          <button 
            @click="openCloneModal(term)"
            class="text-xs bg-accent/10 text-accent px-2 py-1 rounded hover:bg-accent/20 transition-colors"
          >
            Clone This
          </button>
        </div>
      </div>

      <!-- Empty State -->
      <div 
        v-if="terminals.length === 0 && !loading" 
        class="col-span-full text-center py-8 text-gray-500"
      >
        No terminals detected. Ensure MT5 is installed in standard locations.
      </div>
    </div>

    <!-- Clone Modal -->
    <div v-if="showCloneModal" class="fixed inset-0 bg-black/80 backdrop-blur-sm flex items-center justify-center z-50">
      <div class="bg-gray-900 border border-gray-700 rounded-xl p-6 w-full max-w-md shadow-2xl">
        <h3 class="text-lg font-bold mb-4">Clone Terminal</h3>
        <p class="text-sm text-gray-400 mb-6">
          Create a fresh copy of 
          <span class="text-accent">{{ selectedTerminal?.name }}</span> 
          to run another account isolated.
        </p>

        <div class="space-y-4">
          <div>
            <label class="block text-xs uppercase text-gray-500 font-bold mb-1">New Instance Name</label>
            <input 
              v-model="newCloneName" 
              type="text" 
              class="w-full bg-gray-800 border border-gray-700 rounded p-2 text-white focus:border-accent outline-none"
              placeholder="e.g. PropFirm_Account2"
            >
          </div>
        </div>

        <div class="flex justify-end gap-3 mt-8">
          <button 
            @click="showCloneModal = false" 
            class="px-4 py-2 hover:bg-gray-800 rounded text-gray-400"
          >
            Cancel
          </button>
          <button 
            @click="cloneTerminal" 
            class="px-4 py-2 bg-accent hover:bg-accent-hover text-white rounded font-bold disabled:opacity-50 flex items-center gap-2"
            :disabled="!newCloneName || cloning"
          >
            <i v-if="cloning" class="fas fa-spinner fa-spin"></i>
            {{ cloning ? 'Cloning...' : 'Create Clone' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import api from '../../services/api';

const terminals = ref([]);
const loading = ref(false);
const showCloneModal = ref(false);
const selectedTerminal = ref(null);
const newCloneName = ref('');
const cloning = ref(false);

const detectTerminals = async () => {
  loading.value = true;
  try {
    terminals.value = await api.getTerminals();
  } catch (e) {
    console.error(e);
    // alert('Could not detect terminals: ' + (e.response?.data?.detail || e.message));
  } finally {
    loading.value = false;
  }
};

const openCloneModal = (term) => {
  selectedTerminal.value = term;
  newCloneName.value = `${term.name}_Copy`;
  showCloneModal.value = true;
};

const cloneTerminal = async () => {
  if (!selectedTerminal.value || !newCloneName.value) return;
  
  cloning.value = true;
  try {
    await api.cloneTerminal(selectedTerminal.value.path, newCloneName.value);
    
    alert('Terminal cloned successfully!');
    showCloneModal.value = false;
    detectTerminals(); // Refresh list
  } catch (e) {
    console.error(e);
    alert('Cloning failed: ' + (e.response?.data?.detail || e.message));
  } finally {
    cloning.value = false;
  }
};

onMounted(() => {
  detectTerminals();
});
</script>
