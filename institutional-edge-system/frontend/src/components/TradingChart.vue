<template>
  <div ref="chartContainer" class="w-full h-full relative">
    <div v-if="!data || data.length === 0" class="absolute inset-0 flex items-center justify-center text-slate-500 text-xs">
      Loading Chart Data...
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, watch, defineProps } from 'vue';
import { createChart, CandlestickSeries } from 'lightweight-charts';

const props = defineProps({
  data: {
    type: Array,
    default: () => []
  },
  trades: {
    type: Array,
    default: () => []
  },
  symbol: {
    type: String,
    default: ''
  },
  isDark: {
    type: Boolean,
    default: true
  }
});

const chartContainer = ref(null);
let chart = null;
let candlestickSeries = null;
let volumeSeries = null;

// Chart Options
const getChartOptions = (isDark) => {
  return {
    layout: {
      background: { type: 'solid', color: isDark ? '#1e293b' : '#ffffff' }, // Slate-800 or White
      textColor: isDark ? '#94a3b8' : '#333333',
    },
    grid: {
      vertLines: { color: isDark ? '#334155' : '#e1e1e1' },
      horzLines: { color: isDark ? '#334155' : '#e1e1e1' },
    },
    crosshair: {
      mode: 1, // CrosshairMode.Normal
    },
    rightPriceScale: {
      borderColor: isDark ? '#475569' : '#cccccc',
    },
    timeScale: {
      borderColor: isDark ? '#475569' : '#cccccc',
      timeVisible: true,
      secondsVisible: false,
    },
  };
};

const initChart = () => {
  if (!chartContainer.value) return;

  chart = createChart(chartContainer.value, {
    ...getChartOptions(props.isDark),
    width: chartContainer.value.clientWidth,
    height: chartContainer.value.clientHeight,
  });

  // Candlestick Series - v5 API uses addSeries
  candlestickSeries = chart.addSeries(CandlestickSeries, {
    upColor: '#10b981',
    downColor: '#ef4444',
    borderVisible: false,
    wickUpColor: '#10b981',
    wickDownColor: '#ef4444',
  });

  // Volume Series (Optional, add later if needed)
  
  // Initial Data
  if (props.data.length > 0) {
    updateChartData();
  }

  // Resize Observer
  const resizeObserver = new ResizeObserver(entries => {
    if (entries.length === 0 || entries[0].target !== chartContainer.value) { return; }
    const newRect = entries[0].contentRect;
    chart.applyOptions({ width: newRect.width, height: newRect.height });
  });
  resizeObserver.observe(chartContainer.value);
};

const updateChartData = () => {
  if (!candlestickSeries || !props.data) return;
  
  // Format data for lightweight-charts
  // Expected: { time: '2019-04-11', open: 80.01, high: 96.63, low: 76.6, close: 88.65 }
  // Our API returns: { time: 'ISO', open, high, low, close, volume }
  // We need to convert time to unix timestamp (seconds)
  
  const formattedData = props.data.map(d => ({
    time: new Date(d.time).getTime() / 1000,
    open: d.open,
    high: d.high,
    low: d.low,
    close: d.close
  }));
  
  // Sort by time just in case
  formattedData.sort((a, b) => a.time - b.time);
  
  candlestickSeries.setData(formattedData);
  
  updateMarkers();
};

const updateMarkers = () => {
  if (!candlestickSeries || !props.trades) return;
  
  const markers = [];
  
  props.trades.forEach(trade => {
    // Only show markers for open trades on this symbol
    if (trade.symbol !== props.symbol) return;
    
    // Entry Marker
    markers.push({
      time: new Date().getTime() / 1000, // Ideally this should be trade open time, but for live trades we can use current or last bar time
      // Since we don't have exact bar time for entry in the trade object easily mapped to chart bars here without lookup,
      // let's just use the last bar time for "Active" trades visualization
      position: 'inBar',
      color: trade.type === 'BUY' ? '#10b981' : '#ef4444',
      shape: trade.type === 'BUY' ? 'arrowUp' : 'arrowDown',
      text: `${trade.type} @ ${trade.entry}`,
    });
    
    // We can also add PriceLines for Entry, SL, TP
    // But lightweight-charts handles markers better for point-in-time
    // For horizontal lines (SL/TP), we use createPriceLine
  });
  
  // Note: Markers require exact time match with a bar. 
  // For simplicity in this version, we will use PriceLines for active trades instead of markers, 
  // as markers are better for historical trade history.
  
  // Clear existing price lines (not directly supported to "clear all", so we recreate series or track lines)
  // For now, let's just stick to the basic chart rendering. 
  // Advanced annotations can be added in v2.
};

// Watchers
watch(() => props.data, () => {
  updateChartData();
}, { deep: true });

watch(() => props.isDark, (newVal) => {
  if (chart) {
    chart.applyOptions(getChartOptions(newVal));
  }
});

watch(() => props.trades, () => {
    // Update price lines logic here if implemented
    // For now, we rely on the parent to pass data updates
}, { deep: true });


onMounted(() => {
  initChart();
});

onUnmounted(() => {
  if (chart) {
    chart.remove();
    chart = null;
  }
});

// Expose chart instance if needed
defineExpose({
  chart,
  candlestickSeries
});
</script>

<style scoped>
/* No specific styles needed, tailwind handles layout */
</style>
