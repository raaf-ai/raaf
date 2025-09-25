#!/usr/bin/env ruby
# frozen_string_literal: true

# Debug script to generate test HTML with tooltips for browser testing
puts "Generating tooltip debug HTML file..."

html = <<~HTML
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <title>RAAF Tooltip Debug</title>

    <!-- Tailwind CSS -->
    <link href="https://cdn.tailwindcss.com" rel="stylesheet">

    <!-- Preline CSS -->
    <link href="https://preline.co/assets/css/main.min.css" rel="stylesheet">

    <style>
    .hs-tooltip-content {
        z-index: 9999 !important;
        background-color: rgb(17 24 39) !important;
        color: white !important;
        font-size: 12px !important;
        border-radius: 6px !important;
        padding: 8px 12px !important;
        max-width: 300px !important;
        word-wrap: break-word !important;
        box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05) !important;
    }
    </style>
</head>

<body class="bg-gray-50 p-8">
    <h1 class="text-2xl font-bold mb-8">RAAF Tooltip Debug Test</h1>

    <!-- Test 1: Basic Preline Tooltip -->
    <div class="mb-8">
        <h2 class="text-lg font-semibold mb-4">Test 1: Basic Preline Tooltip</h2>
        <div class="hs-tooltip inline-block">
            <button type="button" class="hs-tooltip-toggle px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600">
                Hover me (Basic)
            </button>
            <span class="hs-tooltip-content hs-tooltip-shown:opacity-100 hs-tooltip-shown:visible opacity-0 invisible transition-opacity duration-300 inline-block absolute z-50 py-2 px-3 bg-gray-900 text-xs font-medium text-white rounded-lg shadow-sm dark:bg-slate-700" role="tooltip">
                Basic tooltip test
            </span>
        </div>
    </div>

    <!-- Test 2: Skip Reason Tooltip (Current Implementation) -->
    <div class="mb-8">
        <h2 class="text-lg font-semibold mb-4">Test 2: Skip Reason Tooltip (Current Implementation)</h2>
        <div class="hs-tooltip inline-block skip-reason-tooltip">
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-orange-100 text-orange-800 hs-tooltip-toggle cursor-help">
                Skipped
            </span>
            <span class="hs-tooltip-content hs-tooltip-shown:opacity-100 hs-tooltip-shown:visible opacity-0 invisible transition-opacity duration-200 absolute z-50 py-2 px-3 bg-gray-900 text-xs font-medium text-white rounded-lg shadow-lg max-w-xs whitespace-normal break-words bottom-full left-1/2 transform -translate-x-1/2 mb-2 dark:bg-slate-800" role="tooltip">
                requirements_not_met
            </span>
        </div>
    </div>

    <!-- Test 3: Multiple Tooltips -->
    <div class="mb-8">
        <h2 class="text-lg font-semibold mb-4">Test 3: Multiple Skip Reason Tooltips</h2>
        <div class="space-x-4">
            <div class="hs-tooltip inline-block">
                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-orange-100 text-orange-800 hs-tooltip-toggle cursor-help">
                    Skipped
                </span>
                <span class="hs-tooltip-content hs-tooltip-shown:opacity-100 hs-tooltip-shown:visible opacity-0 invisible transition-opacity duration-200 absolute z-50 py-2 px-3 bg-gray-900 text-xs font-medium text-white rounded-lg shadow-lg max-w-xs whitespace-normal break-words bottom-full left-1/2 transform -translate-x-1/2 mb-2" role="tooltip">
                    Agent requirements not met
                </span>
            </div>

            <div class="hs-tooltip inline-block">
                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 hs-tooltip-toggle cursor-help">
                    Completed
                </span>
                <span class="hs-tooltip-content hs-tooltip-shown:opacity-100 hs-tooltip-shown:visible opacity-0 invisible transition-opacity duration-200 absolute z-50 py-2 px-3 bg-gray-900 text-xs font-medium text-white rounded-lg shadow-lg max-w-xs whitespace-normal break-words bottom-full left-1/2 transform -translate-x-1/2 mb-2" role="tooltip">
                    Task completed successfully
                </span>
            </div>
        </div>
    </div>

    <!-- Debug Console -->
    <div class="mb-8">
        <h2 class="text-lg font-semibold mb-4">Debug Console</h2>
        <div class="bg-black text-green-400 p-4 rounded font-mono text-sm">
            <div id="debug-output">Loading debug info...</div>
        </div>

        <button id="manual-init" class="mt-4 px-4 py-2 bg-green-500 text-white rounded hover:bg-green-600">
            Manual Initialize Tooltips
        </button>

        <button id="check-preline" class="mt-4 ml-2 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600">
            Check Preline Status
        </button>
    </div>

    <!-- Preline JS -->
    <script src="https://preline.co/assets/js/preline.js"></script>

    <script>
    // Debug script
    function debugLog(message) {
        const output = document.getElementById('debug-output');
        output.innerHTML += message + '<br>';
        console.log('🔧 TOOLTIP DEBUG:', message);
    }

    // Wait for DOM to be ready
    document.addEventListener('DOMContentLoaded', function() {
        debugLog('✅ DOM loaded');

        // Check if Preline is available
        setTimeout(function() {
            if (typeof window.HSTooltip !== 'undefined') {
                debugLog('✅ Preline HSTooltip found');
                debugLog('🔍 HSTooltip methods: ' + Object.keys(window.HSTooltip).join(', '));

                // Try auto initialization
                try {
                    window.HSTooltip.autoInit();
                    debugLog('✅ HSTooltip.autoInit() called successfully');
                } catch (e) {
                    debugLog('❌ Error calling autoInit: ' + e.message);
                }
            } else {
                debugLog('❌ Preline HSTooltip NOT found');
                debugLog('🔍 Available window objects: ' + Object.keys(window).filter(k => k.includes('HS')).join(', '));
            }

            // Check for tooltip elements
            const tooltipElements = document.querySelectorAll('.hs-tooltip');
            debugLog('🎯 Found ' + tooltipElements.length + ' tooltip elements');

            const toggleElements = document.querySelectorAll('.hs-tooltip-toggle');
            debugLog('🎯 Found ' + toggleElements.length + ' tooltip toggle elements');

        }, 100);

        // Manual initialization button
        document.getElementById('manual-init').addEventListener('click', function() {
            debugLog('🔄 Manual initialization triggered...');
            if (typeof window.HSTooltip !== 'undefined') {
                try {
                    window.HSTooltip.autoInit();
                    debugLog('✅ Manual autoInit completed');
                } catch (e) {
                    debugLog('❌ Manual autoInit error: ' + e.message);
                }
            } else {
                debugLog('❌ HSTooltip still not available');
            }
        });

        // Check Preline status button
        document.getElementById('check-preline').addEventListener('click', function() {
            debugLog('📊 Preline Status Check:');
            debugLog('- HSTooltip available: ' + (typeof window.HSTooltip !== 'undefined'));
            debugLog('- HSTooltip constructor: ' + typeof window.HSTooltip);
            if (typeof window.HSTooltip !== 'undefined') {
                debugLog('- HSTooltip methods: ' + Object.keys(window.HSTooltip).join(', '));
            }
        });
    });

    // Load event fallback
    window.addEventListener('load', function() {
        debugLog('✅ Window load event triggered');
    });
    </script>
</body>
</html>
HTML

File.write("/tmp/tooltip_debug.html", html)

puts "✅ Debug HTML file created at: /tmp/tooltip_debug.html"
puts ""
puts "📋 Instructions:"
puts "1. Open /tmp/tooltip_debug.html in your browser"
puts "2. Check the debug console output"
puts "3. Hover over the tooltip elements to test"
puts "4. Use the manual buttons to debug initialization"
puts ""
puts "🔧 This will help identify if the issue is:"
puts "- Preline JS not loading"
puts "- HSTooltip not being available"
puts "- Initialization timing issues"
puts "- CSS or HTML structure problems"