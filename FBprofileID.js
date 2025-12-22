// ==UserScript==
// @name         Facebook Profile ID Extractor (Updated Dec 2025 v2)
// @namespace    http://tampermonkey.net/
// @version      1.2
// @description  Displays the numeric Profile ID on any Facebook personal profile page. Expanded patterns for better reliability across different profiles.
// @author       Grok
// @match        https://www.facebook.com/*
// @grant        none
// @run-at       document-end
// ==/UserScript==

(function() {
    'use strict';

    // Only run on potential profile pages
    const path = window.location.pathname;
    if (!path.match(/^\/(profile\.php|[^\/]+)(\/(posts|photos|friends|about)?)?$/)) {
        return;
    }

    function extractProfileID() {
        // Check URL ?id= first
        const urlParams = new URLSearchParams(window.location.search);
        if (urlParams.has('id')) {
            return urlParams.get('id');
        }

        // Comprehensive patterns based on current (late 2025) Facebook structure
        const patterns = [
            /{"user":\{"id":"(\d+)"/,              // Your example
            /"entity_id":"(\d+)"/,
            /"userID":"(\d+)"/,
            /"profile_owner":"(\d+)"/,
            /"profileId":"(\d+)"/,
            /"profile_id":(\d+)/,
            /fb:\/\/profile\/(\d+)/,               // Common in meta tags
            /"id":(\d{10,})[,\}].*?"__typename":"User"/  // Broader JSON match for user object
        ];

        const html = document.documentElement.outerHTML;

        for (const pattern of patterns) {
            const match = html.match(pattern);
            if (match) {
                return match[1];
            }
        }

        return null;
    }

    let profileID = extractProfileID();

    if (profileID) {
        const div = document.createElement('div');
        div.style.position = 'fixed';
        div.style.bottom = '20px';
        div.style.right = '20px';
        div.style.backgroundColor = '#1877F2';
        div.style.color = 'white';
        div.style.padding = '10px 15px';
        div.style.borderRadius = '8px';
        div.style.fontSize = '16px';
        div.style.fontWeight = 'bold';
        div.style.zIndex = '9999';
        div.style.boxShadow = '0 4px 12px rgba(0,0,0,0.3)';
        div.style.cursor = 'pointer';
        div.textContent = `Profile ID: ${profileID}`;
        div.title = 'Click to copy';

        div.onclick = () => {
            navigator.clipboard.writeText(profileID).then(() => {
                div.textContent = 'Copied!';
                setTimeout(() => { div.textContent = `Profile ID: ${profileID}`; }, 2000);
            });
        };

        document.body.appendChild(div);
    } else {
        console.log('Facebook Profile ID not found. Try a hard refresh (Ctrl+Shift+R) or check if this is a personal profile page.');
    }
})();