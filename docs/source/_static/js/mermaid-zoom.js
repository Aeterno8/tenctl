/**
 * Add fullscreen/zoom capability to Mermaid diagrams
 */
(function() {
    'use strict';

    function addZoomButton(mermaidElement) {
        // Remove any existing buttons first
        const existingButtons = mermaidElement.querySelectorAll('button');
        existingButtons.forEach(btn => {
            if (!btn.classList.contains('mermaid-zoom-btn')) {
                btn.remove();
            }
        });

        // Create zoom button
        const zoomBtn = document.createElement('button');
        zoomBtn.className = 'mermaid-zoom-btn';
        zoomBtn.innerHTML = '⛶'; // Fullscreen icon
        zoomBtn.title = 'Open diagram in fullscreen';
        zoomBtn.style.cssText = `
            position: absolute;
            top: 10px;
            right: 10px;
            z-index: 1000;
            background-color: #2196f3;
            color: white;
            border: none;
            padding: 8px 12px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 16px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.2);
            transition: background-color 0.3s;
        `;

        // Hover effect
        zoomBtn.addEventListener('mouseenter', function() {
            this.style.backgroundColor = '#1976d2';
        });
        zoomBtn.addEventListener('mouseleave', function() {
            this.style.backgroundColor = '#2196f3';
        });

        // Click handler - open in modal/fullscreen
        zoomBtn.addEventListener('click', function(e) {
            e.stopPropagation();
            openFullscreen(mermaidElement);
        });

        // Add button to mermaid container
        mermaidElement.style.position = 'relative';
        mermaidElement.appendChild(zoomBtn);
    }

    function openFullscreen(mermaidElement) {
        // Create modal overlay
        const modal = document.createElement('div');
        modal.className = 'mermaid-fullscreen-modal';
        modal.style.cssText = `
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background-color: rgba(0, 0, 0, 0.9);
            z-index: 10000;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        `;

        // Clone the SVG
        const svg = mermaidElement.querySelector('svg');
        if (!svg) return;

        const svgClone = svg.cloneNode(true);
        svgClone.style.cssText = `
            max-width: 95%;
            max-height: 95%;
            background-color: white;
            padding: 20px;
            border-radius: 8px;
        `;

        // Create close button
        const closeBtn = document.createElement('button');
        closeBtn.innerHTML = '✕';
        closeBtn.title = 'Close fullscreen';
        closeBtn.style.cssText = `
            position: absolute;
            top: 20px;
            right: 20px;
            background-color: #f44336;
            color: white;
            border: none;
            padding: 10px 15px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 20px;
            font-weight: bold;
            z-index: 10001;
        `;

        closeBtn.addEventListener('click', function() {
            document.body.removeChild(modal);
        });

        // Close on background click
        modal.addEventListener('click', function(e) {
            if (e.target === modal) {
                document.body.removeChild(modal);
            }
        });

        // Close on ESC key
        const escHandler = function(e) {
            if (e.key === 'Escape') {
                document.body.removeChild(modal);
                document.removeEventListener('keydown', escHandler);
            }
        };
        document.addEventListener('keydown', escHandler);

        modal.appendChild(svgClone);
        modal.appendChild(closeBtn);
        document.body.appendChild(modal);
    }

    // Wait for page load and mermaid diagrams to render
    function initZoomButtons() {
        const mermaidElements = document.querySelectorAll('.mermaid');
        mermaidElements.forEach(function(element) {
            // Only add button if SVG exists (diagram rendered)
            if (element.querySelector('svg')) {
                // Check if button doesn't already exist
                if (!element.querySelector('.mermaid-zoom-btn')) {
                    addZoomButton(element);
                }
            }
        });
    }

    // Initialize after page load
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
            setTimeout(initZoomButtons, 1000);
        });
    } else {
        setTimeout(initZoomButtons, 1000);
    }

    // Re-check after a delay (in case mermaid renders late)
    setTimeout(initZoomButtons, 2000);
    setTimeout(initZoomButtons, 3000);
})();
