import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import { apiInitializer } from "discourse/lib/api";
import { addSearchResultsCallback } from "discourse/lib/search";

const MOBILE_REDUCTION = 2;

const moveAfterBlurb = modifier((element, [component]) => {
  const searchLink = element.closest(".search-link");
  if (searchLink) {
    searchLink.appendChild(element);
    const href = searchLink.getAttribute("href");
    if (href) {
      const match = href.match(/\/(\d+)(?:\/(\d+))?(?:\?|$)/);
      if (match) {
        component.postNumber = match[2] ? parseInt(match[2], 10) : 1;
      }
    }
  }
});

const isLastIndex = (index, length) => index === length - 1;

class SearchThumbnails extends Component {
  @service capabilities;
  @service siteSettings;

  @tracked postNumber = null;

  get maxThumbnails() {
    const setting = this.siteSettings.search_thumbnails_max_count;
    if (setting === 0) {
      return Infinity;
    }
    return this.capabilities.viewport.md
      ? setting
      : Math.max(1, setting - MOBILE_REDUCTION);
  }

  get imageData() {
    const post = this.args.outletArgs.post;
    if (post?.image_search_data) {
      return post.image_search_data;
    }

    const topic = this.args.outletArgs.topic;
    const map = topic?.search_result_image_data_map;
    if (map && this.postNumber) {
      return map[this.postNumber] || {};
    }

    return {};
  }

  get visibleImages() {
    return (this.imageData.urls || []).slice(0, this.maxThumbnails);
  }

  get extraCount() {
    const total = this.imageData.total || 0;
    return total > this.maxThumbnails ? total - this.maxThumbnails : 0;
  }
}

class QuickSearchThumbnails extends SearchThumbnails {
  <template>
    <span class="search-result-thumbnails-wrapper" {{moveAfterBlurb this}}>
      {{#if this.visibleImages.length}}
        <span class="search-result-thumbnails">
          {{#each this.visibleImages as |imageUrl index|}}
            <span class="search-result-thumbnail-wrapper">
              <img class="search-result-thumbnail" src={{imageUrl}} />
              {{#if (isLastIndex index this.visibleImages.length)}}
                {{#if this.extraCount}}
                  <span
                    class="search-result-thumbnail-more"
                  >+{{this.extraCount}}</span>
                {{/if}}
              {{/if}}
            </span>
          {{/each}}
        </span>
      {{/if}}
    </span>
  </template>
}

const injectPostThumbnails = modifier(
  (element, [resultType, siteSettings, capabilities]) => {
    if (resultType.componentName !== "search-result-post") {
      return;
    }

    const setting = siteSettings.search_thumbnails_max_count;
    const maxCount =
      setting === 0
        ? Infinity
        : capabilities.viewport.md
          ? setting
          : Math.max(1, setting - MOBILE_REDUCTION);
    const container = element.closest(".search-result-post");
    if (!container) {
      return;
    }

    const items = container.querySelectorAll(".list .item");
    resultType.results.forEach((result, index) => {
      const item = items[index];
      if (!item) {
        return;
      }

      const imageData = result.image_search_data;
      if (!imageData?.urls?.length) {
        return;
      }

      const searchLink = item.querySelector(".search-link");
      if (
        !searchLink ||
        searchLink.querySelector(".search-result-thumbnails")
      ) {
        return;
      }

      const urls = imageData.urls.slice(0, maxCount);
      const extra = imageData.total > maxCount ? imageData.total - maxCount : 0;

      const wrapper = document.createElement("span");
      wrapper.className = "search-result-thumbnails";

      urls.forEach((url, i) => {
        const thumbWrapper = document.createElement("span");
        thumbWrapper.className = "search-result-thumbnail-wrapper";

        const img = document.createElement("img");
        img.className = "search-result-thumbnail";
        img.src = url;
        thumbWrapper.appendChild(img);

        if (i === urls.length - 1 && extra > 0) {
          const more = document.createElement("span");
          more.className = "search-result-thumbnail-more";
          more.textContent = `+${extra}`;
          thumbWrapper.appendChild(more);
        }

        wrapper.appendChild(thumbWrapper);
      });

      searchLink.appendChild(wrapper);
    });
  }
);

class PostTypeSearchThumbnails extends Component {
  @service capabilities;
  @service siteSettings;

  <template>
    <span
      class="search-thumbnails-injector"
      hidden
      {{injectPostThumbnails
        @outletArgs.resultType
        this.siteSettings
        this.capabilities
      }}
    ></span>
  </template>
}

class FullPageSearchThumbnails extends SearchThumbnails {
  <template>
    {{#if this.visibleImages.length}}
      <div class="search-result-thumbnails">
        {{#each this.visibleImages as |imageUrl index|}}
          <span class="search-result-thumbnail-wrapper">
            <img class="search-result-thumbnail" src={{imageUrl}} />
            {{#if (isLastIndex index this.visibleImages.length)}}
              {{#if this.extraCount}}
                <span
                  class="search-result-thumbnail-more"
                >+{{this.extraCount}}</span>
              {{/if}}
            {{/if}}
          </span>
        {{/each}}
      </div>
    {{/if}}
  </template>
}

export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");

  if (!siteSettings.search_thumbnails_enabled) {
    return;
  }

  addSearchResultsCallback((results) => {
    const imageDataByTopicId = {};

    results.posts?.forEach((post) => {
      if (post.image_search_data && post.topic_id) {
        if (!imageDataByTopicId[post.topic_id]) {
          imageDataByTopicId[post.topic_id] = {};
        }
        imageDataByTopicId[post.topic_id][post.post_number] =
          post.image_search_data;
      }
    });

    results.topics?.forEach((topic) => {
      if (imageDataByTopicId[topic.id]) {
        topic.set("search_result_image_data_map", imageDataByTopicId[topic.id]);
      }
    });

    return results;
  });

  api.renderInOutlet(
    "search-menu-results-topic-title-suffix",
    QuickSearchThumbnails
  );

  api.renderInOutlet("search-menu-results-type-top", PostTypeSearchThumbnails);

  api.renderAfterWrapperOutlet(
    "search-result-entry-blurb-wrapper",
    FullPageSearchThumbnails
  );
});
