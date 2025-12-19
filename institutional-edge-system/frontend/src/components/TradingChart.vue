<template>
  <div ref="chartContainer" class="w-full h-full relative">
    <div v-if="!data || data.length === 0" class="absolute inset-0 flex items-center justify-center text-slate-500 text-xs">
      Loading Chart Data...
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, watch, defineProps, nextTick } from 'vue';
import * as LightweightCharts from 'lightweight-charts';

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
let resizeObserver = null;

// Chart Options
const getChartOptions = (isDark) => {
  return {
    layout: {
      background: { type: 'solid', color: isDark ? '#1e293b' : '#ffffff' },
      textColor: isDark ? '#94a3b8' : '#333333',
    },
    grid: {
      vertLines: { color: isDark ? '#334155' : '#e1e1e1' },
      horzLines: { color: isDark ? '#334155' : '#e1e1e1' },
    },
    crosshair: {
      mode: LightweightCharts.CrosshairMode.Normal,
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

const initChart = async () => {
  if (!chartContainer.value) {
    console.error('TradingChart: Container not available');
    return;
  }

  // Wait for next tick to ensure container has dimensions
  await nextTick();

  const containerWidth = chartContainer.value.clientWidth;
  const containerHeight = chartContainer.value.clientHeight;

  console.log('TradingChart: Initializing chart with dimensions:', containerWidth, 'x', containerHeight);

  if (containerWidth === 0 || containerHeight === 0) {
    console.warn('TradingChart: Container has zero dimensions, retrying...');
    setTimeout(initChart, 100);
    return;
  }

  try {
    chart = LightweightCharts.createChart(chartContainer.value, {
      ...getChartOptions(props.isDark),
      width: containerWidth,
      height: containerHeight,
    });

    // Candlestick Series - v5 API
    candlestickSeries = chart.addSeries(LightweightCharts.CandlestickSeries, {
      upColor: '#10b981',
      downColor: '#ef4444',
      borderVisible: false,
      wickUpColor: '#10b981',
      wickDownColor: '#ef4444',
    });

    console.log('TradingChart: Chart and series created successfully');

    // Initial Data
    if (props.data && props.data.length > 0) {
      updateChartData();
    }

    // Resize Observer
    resizeObserver = new ResizeObserver(entries => {
      if (!chart || entries.length === 0 || entries[0].target !== chartContainer.value) return;
      const newRect = entries[0].contentRect;
      if (newRect.width > 0 && newRect.height > 0) {
        chart.applyOptions({ width: newRect.width, height: newRect.height });
      }
    });
    resizeObserver.observe(chartContainer.value);
  } catch (error) {
    console.error('TradingChart: Error initializing chart:', error);
  }
};

const updateChartData = () => {
  if (!candlestickSeries) {
    console.warn('TradingChart: Series not initialized yet');
    return;
  }
  
  if (!props.data || props.data.length === 0) {
    console.warn('TradingChart: No data to display');
    return;
  }

  console.log('TradingChart: Processing', props.data.length, 'candles');
  
  // Format data for lightweight-charts
  const formattedData = props.data
    .map(d => {
      const timestamp = new Date(d.time).getTime() / 1000;
      return {
        time: timestamp,
        open: Number(d.open),
        high: Number(d.high),
        low: Number(d.low),
        close: Number(d.close)
      };
    })
    .filter(d => !isNaN(d.time) && !isNaN(d.open) && !isNaN(d.high) && !isNaN(d.low) && !isNaN(d.close));
  
  // Sort by time
  formattedData.sort((a, b) => a.time - b.time);
  
  console.log('TradingChart: Setting', formattedData.length, 'valid candles. First:', formattedData[0], 'Last:', formattedData[formattedData.length - 1]);
  
  try {
    candlestickSeries.setData(formattedData);
    chart.timeScale().fitContent();
    console.log('TradingChart: Data set successfully');
  } catch (error) {
    console.error('TradingChart: Error setting data:', error);
  }
  
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
