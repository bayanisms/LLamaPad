<script>
  let { class: className = '', style = '' } = $props();
</script>
<div class={className} {style}>
  <img src="./llamapad.png" alt="LlamaPad" />
</div>
<style>
  div :global(img) {
    width: var(--size, 1rem);
    height: var(--size, 1rem);
    border-radius: 24%;
  }
</style>
