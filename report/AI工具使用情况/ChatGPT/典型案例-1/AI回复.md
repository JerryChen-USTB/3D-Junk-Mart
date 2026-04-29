有，而且**已经出现了几类和你设想高度相似的产品**。不过就我查到的情况看，**“手机直接拍摄 → 自动训练/处理 → 手机端实时查看 → 社区分发”这条链路已经有人做到了 60%–90%，但还没有看到一个把这几件事都做得特别完整、而且明显以“3DGS 社区平台”作为核心定位的头部产品**。([App Store](https://apps.apple.com/us/app/scaniverse-3d-scanner/id1541433223?utm_source=chatgpt.com))

你这个方向最接近的现成产品，第一梯队大概是这几个：

**1. Scaniverse：最像“移动端 3DGS 一条龙”**
Scaniverse 官方和 App Store 都明确写了，它支持用户直接在手机上捕捉 3D 内容，使用 Gaussian splatting、photogrammetry 和 LiDAR 生成模型；而且它主打的是**免费、快速、无限制的 on-device 3D Gaussian splatting**。同时它还支持把作品分享到一个全球地图里，别人可以浏览这些 3D 场景；Niantic 还进一步做了 “Into the Scaniverse” 这种沉浸式浏览入口。也就是说，**移动采集、生成、查看、分享** 这四步它基本都覆盖了。([App Store](https://apps.apple.com/us/app/scaniverse-3d-scanner/id1541433223?utm_source=chatgpt.com))

**2. Luma：更偏“拍完上传/处理后分享”的创作者产品**
Luma 的 iOS 页面写得很明确：用户可以直接用 iPhone 捕捉产品、物体、风景和场景，然后把结果分享到 Web；其 “Interactive Scenes” 页面又说明这些内容可以在 **iOS、Android、Web** 上体验。它非常接近你说的“轻量体验 + 传播”，但它的品牌重心更偏**创作者内容和 3D 展示**，而不是一个原生以“社区互动、点赞、UGC feed”为中心的 3DGS 社区。([Luma](https://lumalabs.ai/ios?utm_source=chatgpt.com))

**3. Polycam：更偏专业生产力/协作，而不是 3DGS 社区**
Polycam 已经把 Gaussian Splatting 放进自己的产品体系里，支持创建 Gaussian Splats，并且提供云端库、查看、编辑、分享、评论、注释等协作能力。它在官网、帮助中心和定价页里都体现出很强的产品化程度。
但它更像是**面向建筑、空间采集、团队协作、专业扫描工作流**的平台，不太像一个面向普通用户的“3DGS 内容社区”。另外它的官方帮助页还特别说明：**Gaussian Splatting 在 Android 设备上不可用**，这对“纯移动普及型平台”是个明显限制。([Poly](https://poly.cam/?utm_source=chatgpt.com))

**4. KIRI Engine：功能很全，甚至已经把手机端 3DGS 编辑做进去了**
KIRI Engine 官网和 App Store 页面都写到，它支持 iPhone、Android、Web，支持 photogrammetry、NeRF/NSR、LiDAR 和 **3D Gaussian Splatting**；而且它不仅支持生成，还支持**手机端直接编辑 3DGS**，例如 masking、sphere/plane/brush 编辑，以及 3DGS 转 mesh。
这说明：**“手机拍 + 服务器/平台处理 + 手机端查看/编辑”** 这条链路，从技术产品形态上已经被证明是可行的。([KIRI Engine: 3D Scanner App](https://www.kiriengine.app/?utm_source=chatgpt.com))

**5. RealityScan：像是“手机拍 → 云端处理 → 分享”的经典闭环，但不主打 3DGS**
Epic 的 RealityScan 官方说明它的移动端可以让用户用手机捕捉、处理并分享高保真扫描结果，而且早期官方新闻稿就明确写了：用户拍完之后由**cloud processing** 把数据转成 3D 模型，再导出到 Sketchfab 分享。
所以如果你把产品抽象成“手机采集 + 后端算 + 手机/Web 浏览 + 社交传播”，RealityScan 也是明显的同类；只是它更偏**摄影测量/RealityCapture 体系**，不是典型以 3D Gaussian Splatting 为主卖点。([RealityScan](https://www.realityscan.com/?utm_source=chatgpt.com))

------

### 这说明什么？

说明你的想法**不是空白市场**，但也**远没有被彻底做完**。现在市面上的产品大致分成三类：

第一类是 **Scaniverse / KIRI** 这种：
已经很接近“普通用户一条龙体验”，尤其 Scaniverse 已经把“拍、生成、分享”做得很顺。([App Store](https://apps.apple.com/us/app/scaniverse-3d-scanner/id1541433223?utm_source=chatgpt.com))

第二类是 **Luma / Polycam** 这种：
更偏创作者工具、展示工具、协作工具，分享能力强，但“社区感”没有那么强，或者不以 3DGS 社交为主。([Luma](https://lumalabs.ai/interactive-scenes/?utm_source=chatgpt.com))

第三类是 **RealityScan** 这种：
核心是移动采集 + 云处理 + 导出/分享，更像现实采集工具链，而不是 3DGS 内容社区。([RealityScan](https://www.realityscan.com/?utm_source=chatgpt.com))

------

### 你这个产品还有没有机会？

我判断：**有，而且机会不小，但不能再只讲“手机拍+训练+查看”了。**
因为这件事本身已经被验证过，甚至被多家公司做出来了。真正的机会更可能在下面几个空位：

**空位 1：把“3DGS”做成真正的内容平台，而不只是扫描工具**
我查到的产品多数都有“分享”，但更像“把模型发一个链接出去”或者“挂到地图/库里”。真正像短视频平台那样围绕 **浏览、推荐、点赞、关注、二创、专题、挑战赛** 构建的 3DGS 原生社区，我没有看到一个特别成熟的通用头部产品。([Niantic Spatial SDK Community](https://community.scaniverse.com/c/its/22?utm_source=chatgpt.com))

**空位 2：把“移动端体验”做到极致一致**
现有产品常常是“采集在手机，深度编辑在 Web/桌面，兼容性因平台而异”。比如 Polycam 就明确写了 Android 上不支持 Gaussian Splatting。你如果能做到**Android/iOS 都顺畅采集、上传、查看、轻编辑、发布**，这本身就是差异化。([Polycam Help Center](https://learn.poly.cam/hc/en-us/articles/34419168797972-Which-Devices-Are-Supported-by-Polycam?utm_source=chatgpt.com))

**空位 3：把“服务化”做得更傻瓜**
你描述的是“用户不用折腾配置”。这点虽然很多产品也在做，但如果你进一步把流程做到：
拍摄引导 → 质量检测 → 自动补拍提醒 → 云端训练队列 → 渐进式预览 → 训练完成推送 → 一键发布社区，
那产品感会明显强于“只是一个扫描 App”。RealityScan 的云处理、KIRI 的编辑、Scaniverse 的分享，都说明每个环节有人做了，但把这些环节统一成一个**消费级闭环**，仍然有空间。([Epic Games Store](https://www.epicgames.com/site/en-US/news/epic-games-releases-free-realityscan-ios-app-for-3d-scanning?utm_source=chatgpt.com))

**空位 4：垂直场景**
通用 3DGS 社区竞争会直接撞上 Scaniverse、Luma、Polycam；但如果你切进某个垂类，比如
二次元手办/潮玩展示、二手交易 3D 展示、文旅地点 3D 打卡、室内设计 before/after、校园/实验室/课程项目展示，
就更有可能做出差异。这个判断是我基于现有产品定位做的推断：Polycam 偏专业，Luma 偏创作者，Scaniverse 偏通用 3D 扫描与地图分享，垂直内容社区仍然可切。([Poly](https://poly.cam/?utm_source=chatgpt.com))

------

### 一句话结论

**有同类产品，而且已经不少；其中 Scaniverse、KIRI Engine、Luma、Polycam、RealityScan 都和你的设想有明显重叠。**
但它们大多是“3D 扫描/创作工具 + 分享能力”，还不完全等于一个以 **3D Gaussian Splatting 为核心内容形态的移动社区平台**。所以你的方向并不是“没人做”，而是更适合从**社区机制、移动端闭环体验、跨平台一致性、垂直场景**这些维度去找差异化。([App Store](https://apps.apple.com/us/app/scaniverse-3d-scanner/id1541433223?utm_source=chatgpt.com))

下一步我可以继续帮你做一版更实用的东西：**把这些竞品整理成对比表（采集方式 / 是否云训练 / 是否 3DGS / 是否手机端查看 / 是否社区分享 / 适合普通用户还是专业用户）**。