// Language redirect for Serbian documentation
(function() {
    // Check if user has Serbian language preference
    var userLang = navigator.language || navigator.userLanguage;
    var currentPath = window.location.pathname;

    // Only redirect from root/index, not if already in /serbian/
    if (currentPath === '/' || currentPath === '/en/latest/' || currentPath.endsWith('/index.html')) {
        if (userLang.startsWith('sr') && !currentPath.includes('/serbian/')) {
            // Redirect to Serbian version
            window.location.href = '/serbian/latest/';
        }
    }
})();
