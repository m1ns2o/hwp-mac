/*
 * Copyright 2021 Hancom Inc. All rights reserved.
 *
 * https://www.hancom.com/
 */
(function() {
	var scripts = window.document.scripts,
		version = window.__hctfwoVersion || String((new Date()).getTime());

	if (scripts) {
		var length = scripts.length,
			userAgent = navigator.userAgent && navigator.userAgent.toLowerCase(),
			useBundleJs = userAgent && !!((userAgent.indexOf("msie ") > -1 || userAgent.indexOf("trident/") > -1)); // isIE

		for (let i = 0; i < length; i++) {
			let scriptNode = scripts[i],
				dataBundle = scriptNode.getAttribute("data-bundle"),
				dataMain = scriptNode.getAttribute("data-main");

			if (dataBundle || dataMain) {
				// 사용하지 않는 변수. 의미가 있는지 확인 후 삭제 필요.
				let dataFrameJs = scriptNode.getAttribute("data-framejs") || "commonFrame/js";

				if (useBundleJs) {
					window.document.write('<script src="' + dataBundle + '.js?' + version + '"></script>');
				} else {
					window.document.write('<script src="' + dataMain + '.js?' + version + '" type="module"></script>');
				}

				break;
			}
		}
	}
}());
