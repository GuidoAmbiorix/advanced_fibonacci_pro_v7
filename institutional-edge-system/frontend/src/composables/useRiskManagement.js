import { ref } from 'vue'
import axios from 'axios'

export function useRiskManagement(API_URL, showToastNotification) {
    const killSwitchActive = ref(false)
    const riskStatus = ref({
        max_dd_percent: 7.0,
        current_dd_percent: 0.0,
        daily_dd_percent: 0.0,
        total_dd_percent: 0.0,
        kill_switch_reason: ''
    })

    const toggleKillSwitch = async () => {
        try {
            const newState = !killSwitchActive.value
            // Optimistic update
            killSwitchActive.value = newState
            
            await axios.post(`${API_URL}/api/settings/kill-switch`, { active: newState })
            
            if (showToastNotification) {
                showToastNotification(
                    newState ? '💀 GLOBAL KILL SWITCH ACTIVATED' : '🛡️ System Security Restored',
                    newState ? 'error' : 'success',
                    5000
                )
            }
        } catch (e) {
            console.error("Failed to toggle kill switch", e)
            if (showToastNotification) showToastNotification("Failed to toggle Kill Switch", 'error')
            killSwitchActive.value = !killSwitchActive.value // Revert
        }
    }

    return {
        killSwitchActive,
        riskStatus,
        toggleKillSwitch
    }
}
