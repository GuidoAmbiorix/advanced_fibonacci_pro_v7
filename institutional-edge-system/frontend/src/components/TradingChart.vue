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
  
  updateTradeLines();
};

const priceLines = [];

const updateTradeLines = () => {
  if (!candlestickSeries) return;

  // Clear existing lines
  priceLines.forEach(line => {
    candlestickSeries.removePriceLine(line);
  });
  priceLines.length = 0; // Clear array

  if (!props.trades) return;

  props.trades.forEach(trade => {
    if (trade.symbol !== props.symbol) return;

    // Entry Line
    const entryLine = candlestickSeries.createPriceLine({
      price: parseFloat(trade.entry),
      color: trade.type === 'BUY' ? '#3b82f6' : '#f59e0b', // Blue/Orange for entry to distinguish
      lineWidth: 1,
      lineStyle: 2, // Dashed
      axisLabelVisible: true,
      title: `${trade.type} #${trade.ticket}`,
    });
    priceLines.push(entryLine);

    // SL Line
    if (trade.sl && parseFloat(trade.sl) > 0) {
      const slLine = candlestickSeries.createPriceLine({
        price: parseFloat(trade.sl),
        color: '#ef4444', // Red
        lineWidth: 2,
        lineStyle: 0, // Solid
        axisLabelVisible: true,
        title: `SL`,
      });
      priceLines.push(slLine);
    }

    // TP Line
    if (trade.tp && parseFloat(trade.tp) > 0) {
      const tpLine = candlestickSeries.createPriceLine({
        price: parseFloat(trade.tp),
        color: '#10b981', // Green
        lineWidth: 2,
        lineStyle: 0, // Solid
        axisLabelVisible: true,
        title: `TP`,
      });
      priceLines.push(tpLine);
    }
  });
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
    updateTradeLines();
}, { deep: true });

watch(() => props.symbol, () => {
    updateTradeLines();
});


onMounted(() => {
  initChart();
});

onUnmounted(() => {
  if (chart) {
    chart.remove();
    chart = null;
  }
});

const updateCandle = (candle) => {
  if (!candlestickSeries) return;
  candlestickSeries.update(candle);
};

// Expose chart instance and methods
defineExpose({
  chart,
  updateCandle
});
</script>

<style scoped>
/* No specific styles needed, tailwind handles layout */
</style>
