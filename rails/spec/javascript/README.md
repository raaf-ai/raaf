# RAAF Stimulus Controller Tests

This directory contains tests for the RAAF span detail Stimulus controller.

## Files

- `controllers/span_detail_controller.spec.js` - Jest unit tests for the Stimulus controller
- `test_runner.html` - Browser-based test runner for cross-browser compatibility testing
- `setup.js` - Jest configuration and test setup

## Running Tests

### Jest Tests (Unit Testing)

```bash
# Install dependencies
npm install

# Run tests
npm test

# Run tests with coverage
npm run test:coverage

# Run tests in watch mode
npm run test:watch
```

### Browser Tests (Cross-Browser Testing)

Open `test_runner.html` in different browsers:

```bash
# macOS
open test_runner.html

# Or with specific browser
open -a "Google Chrome" test_runner.html
open -a "Safari" test_runner.html
open -a "Firefox" test_runner.html

# Linux
xdg-open test_runner.html
```

### Ruby Test Runner

Run the comprehensive test suite:

```bash
cd rails/
ruby run_stimulus_tests.rb
```

## Test Coverage

The tests cover:

### Core Functionality
- ✅ Stimulus controller initialization
- ✅ Section expand/collapse toggling
- ✅ Icon state management (chevron rotation)
- ✅ Button text updates
- ✅ CSS class manipulation

### Specific Actions
- ✅ `toggleSection` - General section toggle
- ✅ `toggleToolInput` - Tool input parameter sections
- ✅ `toggleToolOutput` - Tool output result sections
- ✅ `toggleAttributeGroup` - Grouped attribute sections
- ✅ `toggleErrorDetail` - Error detail expansion
- ✅ `toggleValue` - Long value content expansion
- ✅ `toggleAttributesView` - Structured vs raw JSON view
- ✅ `copyJson` - JSON content to clipboard
- ✅ `copyToClipboard` - Arbitrary text to clipboard

### Error Handling
- ✅ Missing DOM elements
- ✅ Missing data attributes
- ✅ Clipboard API unavailability
- ✅ Rapid consecutive interactions

### Cross-Browser Compatibility
- ✅ Event delegation
- ✅ CSS classList manipulation
- ✅ Dataset attribute access
- ✅ Clipboard API fallbacks
- ✅ Custom event dispatching

### Integration Scenarios
- ✅ Multiple sections working independently
- ✅ Initially collapsed sections
- ✅ Event target variations
- ✅ Real DOM manipulation

## Browser Compatibility

The controller is tested and works in:
- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

### Supported Features
- Modern JavaScript (ES2015+)
- CSS classList API
- Dataset attributes
- Clipboard API (with fallback)
- Custom events
- Event delegation

### Fallbacks
- Old clipboard API using `document.execCommand()`
- Graceful degradation for missing APIs
- Console warnings for debugging

## Usage in Rails

To use the Stimulus controller in your Rails application:

1. **Include the controller** in your application:
   ```javascript
   // app/javascript/controllers/span_detail_controller.js
   import SpanDetailController from "../../../vendor/local_gems/raaf/rails/app/javascript/controllers/span_detail_controller"
   application.register("span-detail", SpanDetailController)
   ```

2. **Add data attributes** to your HTML:
   ```erb
   <div data-controller="span-detail">
     <button data-action="click->span-detail#toggleSection" 
             data-target="my-section">
       <i class="bi bi-chevron-right toggle-icon"></i>
       Toggle
     </button>
     <div id="my-section" class="hidden">Content</div>
   </div>
   ```

3. **Required CSS classes**:
   - `.hidden` - Hide/show sections
   - `.bi-chevron-right`, `.bi-chevron-down` - Bootstrap Icons
   - `.toggle-icon` - Icon elements to rotate
   - `.button-text` - Text elements to update

## Troubleshooting

### Tests Failing
- Ensure Node.js and npm are installed
- Run `npm install` to install dependencies
- Check Jest configuration in `package.json`

### Browser Tests Not Working
- Check browser console for JavaScript errors
- Ensure Bootstrap Icons CSS is loaded
- Verify data attributes are properly set

### Controller Not Responding
- Verify Stimulus is loaded and configured
- Check data-controller attribute is set
- Ensure data-action follows Stimulus format
- Check browser console for errors

### Missing Features
- Confirm browser supports required APIs
- Check for JavaScript errors in console
- Verify DOM structure matches controller expectations
