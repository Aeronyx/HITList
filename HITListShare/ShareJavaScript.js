// Brief 90: Safari on iPhone and iPad runs this on the page being shared and hands its result to the share extension
// (NSExtensionJavaScriptPreprocessingFile in Info.plist): the page's address, its title and any selected text. It reads
// the page and changes nothing.
var HITListShare = function () {};

HITListShare.prototype = {
    run: function (args) {
        var selection = "";
        try {
            selection = window.getSelection ? String(window.getSelection()) : "";
        } catch (e) {
            selection = "";
        }
        args.completionFunction({
            "URL": document.URL,
            "title": document.title,
            "selection": selection
        });
    },
    finalize: function (args) {}
};

var ExtensionPreprocessingJS = new HITListShare();
