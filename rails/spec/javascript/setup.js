// Jest setup file for RAAF Rails JavaScript tests

// Import jest-dom matchers
require('@testing-library/jest-dom');

// Mock global console to reduce noise in tests
const originalConsole = global.console;

beforeEach(() => {
  // Mock console methods but allow them to work in verbose mode
  global.console = {
    ...originalConsole,
    log: process.env.VERBOSE ? originalConsole.log : jest.fn(),
    warn: process.env.VERBOSE ? originalConsole.warn : jest.fn(),
    error: originalConsole.error, // Always show errors
    info: process.env.VERBOSE ? originalConsole.info : jest.fn(),
  };
});

afterEach(() => {
  global.console = originalConsole;
});

// Mock clipboard API for tests
Object.assign(navigator, {
  clipboard: {
    writeText: jest.fn(() => Promise.resolve()),
    readText: jest.fn(() => Promise.resolve('')),
  },
});

// Mock Stimulus Controller class for tests
global.Controller = class {
  constructor() {
    this.element = null;
  }
  
  dispatch(eventName, detail) {
    const event = new CustomEvent(eventName, detail);
    if (this.element) {
      this.element.dispatchEvent(event);
    }
  }
};

// Add custom matchers for DOM testing
expect.extend({
  toBeVisible(received) {
    const pass = !received.classList.contains('hidden') && 
                received.style.display !== 'none';
    
    if (pass) {
      return {
        message: () => `expected ${received} not to be visible`,
        pass: true,
      };
    } else {
      return {
        message: () => `expected ${received} to be visible`,
        pass: false,
      };
    }
  },
  
  toBeHidden(received) {
    const pass = received.classList.contains('hidden') || 
                received.style.display === 'none';
    
    if (pass) {
      return {
        message: () => `expected ${received} not to be hidden`,
        pass: true,
      };
    } else {
      return {
        message: () => `expected ${received} to be hidden`,
        pass: false,
      };
    }
  },
  
  toHaveChevronDirection(received, direction) {
    const hasRight = received.classList.contains('bi-chevron-right');
    const hasDown = received.classList.contains('bi-chevron-down');
    const pass = (direction === 'right' && hasRight && !hasDown) ||
                 (direction === 'down' && hasDown && !hasRight);
    
    if (pass) {
      return {
        message: () => `expected ${received} not to have chevron direction ${direction}`,
        pass: true,
      };
    } else {
      return {
        message: () => `expected ${received} to have chevron direction ${direction}`,
        pass: false,
      };
    }
  },
});

// Add utility functions for tests
global.createMockEvent = (options = {}) => {
  return {
    preventDefault: jest.fn(),
    stopPropagation: jest.fn(),
    currentTarget: null,
    target: null,
    ...options
  };
};

global.createMockButton = (attributes = {}) => {
  const button = document.createElement('button');
  Object.keys(attributes).forEach(key => {
    if (key.startsWith('data-')) {
      button.setAttribute(key, attributes[key]);
    } else {
      button[key] = attributes[key];
    }
  });
  return button;
};

global.createMockSection = (id, options = {}) => {
  const section = document.createElement('div');
  section.id = id;
  
  if (options.hidden) {
    section.classList.add('hidden');
  }
  
  if (options.initiallyCollapsed) {
    section.setAttribute('data-initially-collapsed', 'true');
  }
  
  if (options.content) {
    section.textContent = options.content;
  }
  
  return section;
};

// Debug helper for tests
global.debugElement = (element) => {
  console.log('Element:', element.tagName);
  console.log('Classes:', element.className);
  console.log('Attributes:', element.attributes);
  console.log('Data:', element.dataset);
  console.log('Style:', element.style.cssText);
};
